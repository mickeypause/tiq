package expo.modules.qaoverlay

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.UUID

internal object QaLinearSession {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private var client: QaLinearClient? = null
  private var initialized = false
  private var attempted = false
  // shortcut: drafts and submission recovery live for this process; persist together before supporting process-restored drafts.
  private var submissionId: String? = null
  private var pendingInput: JSONObject? = null
  private val uploaded = mutableMapOf<String, String>()
  var configured by mutableStateOf(false); private set
  var authenticated by mutableStateOf(false); private set
  var busy by mutableStateOf(false); private set
  var progress by mutableStateOf(""); private set
  var viewer by mutableStateOf(""); private set
  var teams by mutableStateOf(emptyList<QaLinearChoice>()); private set
  var states by mutableStateOf(emptyList<QaLinearChoice>()); private set
  var teamId by mutableStateOf(""); private set
  var stateId by mutableStateOf("")
  var error by mutableStateOf<String?>(null)
  var created by mutableStateOf<QaLinearIssue?>(null)
  var pending by mutableStateOf(false); private set
  val locked get() = busy || pending
  val canDiscardDraft get() = !busy && submissionId == null

  fun initialize(context: Context) {
    if (initialized) return
    initialized = true
    val meta = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA).metaData
    val id = meta?.getString("expo.modules.qaoverlay.LINEAR_CLIENT_ID") ?: return
    val redirect = meta.getString("expo.modules.qaoverlay.LINEAR_REDIRECT_URI") ?: return
    val config = QaLinearConfig(id, redirect, meta.getString("expo.modules.qaoverlay.LINEAR_TEAM_ID"))
    client = QaLinearClient(config, QaLinearVault(context.applicationContext, config)); configured = true
  }
  private fun run(action: suspend (QaLinearClient) -> Unit) {
    val api = client ?: return
    if (busy) return
    busy = true
    scope.launch {
      try { action(api) } catch (failure: Exception) {
        if (failure is QaLinearUnauthorized) {
          withContext(Dispatchers.IO) { runCatching { api.vault.update { it.remove("tokens") } } }
          authenticated = false; teams = emptyList(); states = emptyList()
        }
        error = (failure.message ?: "Linear request failed. Your draft is safe.") + if (pending) " Check submission before making another report." else ""
      } finally { busy = false }
    }
  }
  fun open(context: Context) {
    initialize(context)
    if (!configured || busy || authenticated || attempted) return
    attempted = true
    run { api ->
      progress = "Loading Linear…"
      if (withContext(Dispatchers.IO) { api.vault.read().has("tokens") }) workspace(api, context)
      else { busy = false; signIn(context) }
    }
  }
  fun signIn(context: Context) {
    if (busy) return
    run { api ->
      val state = QaLinearOAuth.random(); val verifier = QaLinearOAuth.random()
      withContext(Dispatchers.IO) { api.vault.update { it.put("auth", JSONObject().put("state", state).put("verifier", verifier).put("started", System.currentTimeMillis())) } }
      val address = "https://linear.app/oauth/authorize?" + QaLinearOAuth.form(mapOf("client_id" to api.config.clientId, "redirect_uri" to api.config.redirect, "response_type" to "code", "scope" to "read,write", "state" to state, "code_challenge" to QaLinearOAuth.challenge(verifier), "code_challenge_method" to "S256"))
      context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(address)))
    }
  }
  suspend fun callback(context: Context, address: String) {
    initialize(context)
    val api = client ?: return
    if (busy) return
    busy = true; progress = "Signing in to Linear…"
    try {
      val auth = withContext(Dispatchers.IO) { api.vault.read().optJSONObject("auth") } ?: error("No Linear sign-in is pending. Please try again.")
      require(System.currentTimeMillis() - auth.getLong("started") in 0..600000) { "Linear sign-in expired. Please try again." }
      val code = QaLinearOAuth.callback(address, api.config.redirect, auth.getString("state")) ?: error("Linear sign-in could not be verified. Please try again.")
      withContext(Dispatchers.IO) { api.vault.update { it.remove("auth") } }
      api.authorize(code, auth.getString("verifier")); workspace(api, context)
    } catch (failure: Exception) { error = failure.message ?: "Linear sign-in failed." }
    finally { busy = false }
  }
  private suspend fun workspace(api: QaLinearClient, context: Context) {
    val (user, available) = api.teams()
    require(available.isNotEmpty()) { "This account has no accessible Linear teams." }
    val preferences = context.getSharedPreferences("rn-qa-overlay.linear", Context.MODE_PRIVATE)
    val preferred = api.config.team ?: preferences.getString("team", null)
    val selected = available.firstOrNull { it.id.equals(preferred, ignoreCase = true) }
    require(api.config.team == null || selected != null) { "The configured Linear team is not accessible to this account." }
    viewer = user; teams = available; teamId = (selected ?: available.first()).id
    workflow(api, context, teamId); authenticated = true
  }
  private suspend fun workflow(api: QaLinearClient, context: Context, team: String) {
    val available = api.states(team)
    require(available.isNotEmpty()) { "This Linear team has no workflow states." }
    teamId = team
    states = available; stateId = (available.firstOrNull { it.type == "triage" } ?: available.firstOrNull { it.type == "backlog" } ?: available.first()).id
    context.getSharedPreferences("rn-qa-overlay.linear", Context.MODE_PRIVATE).edit().putString("team", teamId).apply()
  }
  fun selectTeam(id: String, context: Context) {
    if (locked || teams.none { it.id == id }) return
    run { api -> progress = "Loading workflow…"; workflow(api, context, id) }
  }
  fun signOut() {
    if (locked) return
    run { api ->
      withContext(Dispatchers.IO) { api.vault.clear() }
      authenticated = false; teams = emptyList(); states = emptyList(); teamId = ""; stateId = ""; viewer = ""; uploaded.clear()
    }
  }
  fun submit() {
    if (!authenticated || busy || QaDraft.importing || (pendingInput == null && (QaDraft.title.isBlank() || states.none { it.id == stateId }))) return
    run { api ->
      progress = if (pending) "Checking submission…" else "Creating ticket…"
      submissionId?.let { id -> api.find(id)?.let { complete(it); return@run } }
      if (pendingInput == null) {
        var body = QaDraft.description
        for ((index, attachment) in QaDraft.attachments.toList().withIndex()) {
          progress = "Uploading attachment ${index + 1} of ${QaDraft.attachments.size}…"
          val asset = uploaded[attachment.file.path] ?: api.upload(attachment.file,
            android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(attachment.file.extension.lowercase()) ?: if (attachment.video) "video/mp4" else "image/jpeg"
          ).also { uploaded[attachment.file.path] = it }
          body += "\n\n![${if (attachment.video) "Video" else "Image"}]($asset)"
        }
        if (submissionId == null) submissionId = UUID.randomUUID().toString()
        pendingInput = JSONObject().put("id", submissionId).put("title", QaDraft.title.trim()).put("description", body).put("teamId", teamId).put("stateId", stateId)
        pending = true
      }
      progress = "Creating ticket…"
      complete(api.create(requireNotNull(pendingInput)))
    }
  }
  fun discardDraft() {
    if (!canDiscardDraft || QaDraft.importing) return
    uploaded.clear()
    stateId = (states.firstOrNull { it.type == "triage" } ?: states.firstOrNull { it.type == "backlog" } ?: states.firstOrNull())?.id ?: ""
    error = null; QaDraft.error = null
    QaDraft.discard()
  }
  fun editPending() { if (!busy) { pendingInput = null; pending = false } }
  private fun complete(issue: QaLinearIssue) {
    created = issue; submissionId = null; pendingInput = null; pending = false; uploaded.clear(); QaDraft.discard()
  }
}
