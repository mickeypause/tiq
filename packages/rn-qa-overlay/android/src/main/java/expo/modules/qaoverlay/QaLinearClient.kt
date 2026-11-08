package expo.modules.qaoverlay

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class QaLinearConfig(val clientId: String, val redirect: String, val team: String?)
internal data class QaLinearChoice(val id: String, val name: String, val type: String = "", val icon: String? = null, val color: String? = null) {
  val statusIcon: String get() = when (type) {
    "triage" -> "IssueStatusTriage"
    "backlog" -> "IssueStatusBacklog"
    "unstarted" -> "IssueStatusTodo"
    "started" -> "IssueStatusStarted"
    "completed" -> "IssueStatusDone"
    "canceled" -> "StatusCanceled"
    "duplicate" -> "StatusDuplicate"
    else -> "IssueStatusTodo"
  }
}
internal data class QaLinearIssue(val id: String, val identifier: String, val url: String)
internal class QaLinearUnauthorized : Exception("Your Linear session expired. Please sign in again.")

// Credentials and in-flight PKCE material stay encrypted outside Android backup.
internal class QaLinearVault(context: Context, config: QaLinearConfig) {
  private val alias = "rn-qa-overlay.linear." + MessageDigest.getInstance("SHA-256").digest((config.clientId + config.redirect).toByteArray()).joinToString("") { "%02x".format(it) }
  private val file = AtomicFile(File(context.noBackupFilesDir, alias))
  private fun key(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    return store.getKey(alias, null) as? SecretKey ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
      init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
    }.generateKey()
  }
  @Synchronized fun read(): JSONObject {
    if (!file.baseFile.exists()) return JSONObject()
    val bytes = file.readFully()
    require(bytes.size > 12) { "Secure Linear credentials are unreadable." }
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
    return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
  }
  @Synchronized fun update(change: (JSONObject) -> Unit) {
    val data = read().also(change)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
    val bytes = cipher.iv + cipher.doFinal(data.toString().toByteArray(Charsets.UTF_8))
    val output = file.startWrite()
    try { output.write(bytes); file.finishWrite(output) } catch (error: Exception) { file.failWrite(output); throw error }
  }
  @Synchronized fun clear() { file.delete() }
}

internal object QaLinearOAuth {
  fun random(): String = encode(ByteArray(32).also { SecureRandom().nextBytes(it) })
  private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
  fun challenge(verifier: String): String = encode(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))
  fun form(values: Map<String, String>): String = values.entries.joinToString("&") { URLEncoder.encode(it.key, "UTF-8") + "=" + URLEncoder.encode(it.value, "UTF-8") }
  fun callback(address: String, redirect: String, state: String): String? = runCatching {
    val uri = URI(address); val expected = URI(redirect)
    require(uri.scheme == expected.scheme && uri.host == expected.host && uri.path == expected.path && uri.port == expected.port && uri.userInfo == null && uri.fragment == null)
    val pairs = (uri.rawQuery ?: "").split('&').map { it.split('=', limit = 2).let { p -> java.net.URLDecoder.decode(p[0], "UTF-8") to java.net.URLDecoder.decode(p.getOrElse(1) { "" }, "UTF-8") } }
    require(pairs.count { it.first == "state" } == 1 && pairs.count { it.first == "code" } == 1 && pairs.none { it.first == "error" })
    require(MessageDigest.isEqual(pairs.first { it.first == "state" }.second.toByteArray(), state.toByteArray()))
    pairs.first { it.first == "code" }.second.also { require(it.isNotBlank()) }
  }.getOrNull()
}

internal class QaLinearClient(val config: QaLinearConfig, val vault: QaLinearVault) {
  private val refresh = Mutex()
  private fun connection(address: String, method: String): HttpURLConnection = (URL(address).openConnection() as HttpURLConnection).apply {
    requestMethod = method; instanceFollowRedirects = false; connectTimeout = 15000; readTimeout = 60000; useCaches = false
  }
  private fun response(connection: HttpURLConnection): JSONObject {
    val status = connection.responseCode
    if (status == 401) throw QaLinearUnauthorized()
    require(status in 200..299) { if (status == 429) "Linear's rate limit was reached. Try again later." else "Linear request failed (HTTP $status). Your draft is safe." }
    return connection.inputStream.bufferedReader().use { JSONObject(it.readText()) }
  }
  private fun token(fields: Map<String, String>): JSONObject {
    val c = connection("https://api.linear.app/oauth/token", "POST")
    try {
      c.doOutput = true; c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
      c.outputStream.use { it.write(QaLinearOAuth.form(fields).toByteArray()) }
      if (c.responseCode == 400) throw QaLinearUnauthorized()
      val data = response(c)
      require(data.getString("access_token").isNotEmpty() && data.getString("refresh_token").isNotEmpty() && data.getLong("expires_in") > 0) { "Linear returned invalid credentials." }
      return JSONObject().put("access", data.getString("access_token")).put("refresh", data.getString("refresh_token")).put("expires", System.currentTimeMillis() + data.getLong("expires_in") * 1000)
    } finally { c.disconnect() }
  }
  suspend fun authorize(code: String, verifier: String) = withContext(Dispatchers.IO) {
    val tokens = token(mapOf("grant_type" to "authorization_code", "client_id" to config.clientId, "redirect_uri" to config.redirect, "code" to code, "code_verifier" to verifier))
    vault.update { it.put("tokens", tokens); it.remove("auth") }
  }
  private suspend fun access(force: Boolean = false): String = refresh.withLock {
    withContext(Dispatchers.IO) {
      val stored = vault.read().optJSONObject("tokens") ?: throw QaLinearUnauthorized()
      if (!force && stored.getLong("expires") > System.currentTimeMillis() + 60000) return@withContext stored.getString("access")
      try {
        val next = token(mapOf("grant_type" to "refresh_token", "client_id" to config.clientId, "refresh_token" to stored.getString("refresh")))
        vault.update { it.put("tokens", next) }; next.getString("access")
      } catch (error: QaLinearUnauthorized) { vault.update { it.remove("tokens") }; throw error }
    }
  }
  private suspend fun query(query: String, variables: JSONObject = JSONObject(), retry: Boolean = true): JSONObject {
    val access = access()
    try {
      return withContext(Dispatchers.IO) {
        val c = connection("https://api.linear.app/graphql", "POST")
        try {
          c.doOutput = true; c.setRequestProperty("Content-Type", "application/json"); c.setRequestProperty("Authorization", "Bearer $access")
          c.outputStream.use { it.write(JSONObject().put("query", query).put("variables", variables).toString().toByteArray()) }
          val result = response(c)
          val errors = result.optJSONArray("errors")
          if (errors != null && errors.length() > 0) {
            if ((0 until errors.length()).any { errors.getJSONObject(it).optJSONObject("extensions")?.optString("code")?.contains("AUTHENTICAT") == true }) throw QaLinearUnauthorized()
            error("Linear could not complete the request. Check your workspace permissions and try again.")
          }
          result.getJSONObject("data")
        } finally { c.disconnect() }
      }
    } catch (error: QaLinearUnauthorized) {
      if (!retry) throw error
      access(true)
      return query(query, variables, false)
    }
  }
  suspend fun teams(): Pair<String, List<QaLinearChoice>> {
    val result = mutableListOf<QaLinearChoice>(); var cursor: String? = null; var viewer: String
    do {
      val data = query("query Teams(\$after:String){viewer{name organization{name}} teams(first:100,after:\$after){nodes{id name key icon color} pageInfo{hasNextPage endCursor}}}", JSONObject().put("after", cursor ?: JSONObject.NULL))
      val user = data.getJSONObject("viewer"); viewer = user.getString("name") + " · " + user.getJSONObject("organization").getString("name")
      val connection = data.getJSONObject("teams"); val nodes = connection.getJSONArray("nodes")
      for (i in 0 until nodes.length()) nodes.getJSONObject(i).let { result.add(QaLinearChoice(it.getString("id"), it.getString("name"), icon = it.optString("icon").takeUnless { value -> value.isEmpty() || value == "null" }, color = it.optString("color").takeUnless { value -> value.isEmpty() || value == "null" })) }
      cursor = nextPage(connection, cursor)
    } while (cursor != null)
    return viewer to result
  }
  suspend fun states(team: String): List<QaLinearChoice> {
    val result = mutableListOf<QaLinearChoice>(); var cursor: String? = null
    do {
      val data = query("query States(\$team:String!,\$after:String){team(id:\$team){states(first:100,after:\$after){nodes{id name type color} pageInfo{hasNextPage endCursor}}}}", JSONObject().put("team", team).put("after", cursor ?: JSONObject.NULL))
      val connection = data.getJSONObject("team").getJSONObject("states"); val nodes = connection.getJSONArray("nodes")
      for (i in 0 until nodes.length()) nodes.getJSONObject(i).let { result.add(QaLinearChoice(it.getString("id"), it.getString("name"), it.getString("type"), color = it.optString("color").takeUnless { value -> value.isEmpty() || value == "null" })) }
      cursor = nextPage(connection, cursor)
    } while (cursor != null)
    return result
  }
  private fun nextPage(connection: JSONObject, previous: String?): String? {
    val page = connection.getJSONObject("pageInfo")
    if (!page.getBoolean("hasNextPage")) return null
    val next = page.getString("endCursor")
    require(next.isNotEmpty() && next != previous) { "Linear pagination did not advance." }; return next
  }
  suspend fun upload(file: File, mime: String): String {
    require(file.length() in 1..QaDraft.MAX_BYTES) { "Choose a non-empty file smaller than 100 MB." }
    val payload = query("mutation Upload(\$type:String!,\$name:String!,\$size:Int!){fileUpload(contentType:\$type,filename:\$name,size:\$size){success uploadFile{uploadUrl assetUrl headers{key value}}}}", JSONObject().put("type", mime).put("name", file.name).put("size", file.length())).getJSONObject("fileUpload")
    require(payload.getBoolean("success")) { "Linear did not authorize the attachment upload." }
    val upload = payload.getJSONObject("uploadFile"); val target = URI(upload.getString("uploadUrl")); val asset = URI(upload.getString("assetUrl"))
    require(target.scheme == "https" && target.host != null && target.userInfo == null && asset.scheme == "https" && asset.host == "uploads.linear.app" && asset.userInfo == null) { "Linear returned an invalid upload destination." }
    withContext(Dispatchers.IO) {
      val c = connection(target.toString(), "PUT")
      try {
        c.doOutput = true; c.setFixedLengthStreamingMode(file.length()); c.setRequestProperty("Content-Type", mime); c.setRequestProperty("Cache-Control", "public, max-age=31536000")
        val headers = upload.getJSONArray("headers")
        for (i in 0 until headers.length()) {
          val header = headers.getJSONObject(i); val key = header.getString("key")
          require(key.lowercase() !in listOf("authorization", "cookie", "proxy-authorization")) { "Linear returned unsupported upload headers." }
          c.setRequestProperty(key, header.getString("value"))
        }
        c.outputStream.use { output -> file.inputStream().use { it.copyTo(output) } }
        require(c.responseCode in 200..299) { "Attachment upload failed. Your draft is safe." }
      } finally { c.disconnect() }
    }
    return asset.toString()
  }
  suspend fun create(input: JSONObject): QaLinearIssue {
    val result = query("mutation Create(\$input:IssueCreateInput!){issueCreate(input:\$input){success issue{id identifier url}}}", JSONObject().put("input", input)).getJSONObject("issueCreate")
    require(result.getBoolean("success")) { "Linear did not confirm ticket creation. Check submission before retrying." }
    return issue(result.getJSONObject("issue"))
  }
  suspend fun find(id: String): QaLinearIssue? {
    val nodes = query("query Find(\$id:ID!){issues(filter:{id:{eq:\$id}},first:1){nodes{id identifier url}}}", JSONObject().put("id", id)).getJSONObject("issues").getJSONArray("nodes")
    return if (nodes.length() == 0) null else issue(nodes.getJSONObject(0))
  }
  private fun issue(data: JSONObject): QaLinearIssue {
    val address = URI(data.getString("url")); require(address.scheme == "https" && address.host == "linear.app" && address.userInfo == null) { "Linear returned an invalid ticket receipt." }
    return QaLinearIssue(data.getString("id"), data.getString("identifier"), address.toString())
  }
}
