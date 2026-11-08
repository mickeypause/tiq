package expo.modules.qaoverlay

import android.content.Context
import android.graphics.Bitmap
import android.media.ThumbnailUtils
import android.net.Uri
import android.util.Size
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID

data class QaAttachment(val file: File, val video: Boolean, val thumbnail: Bitmap?)

object QaDraft {
  var title by mutableStateOf("")
  var description by mutableStateOf("")
  var error by mutableStateOf<String?>(null)
  var importing by mutableStateOf(false)
  var recording by mutableStateOf(false)
  val attachments = mutableStateListOf<QaAttachment>()
  val hasContent get() = title.isNotBlank() || description.isNotBlank() || attachments.isNotEmpty()
  const val MAX_BYTES = 100L * 1024 * 1024

  fun newFile(context: Context, suffix: String): File {
    val directory = File(context.cacheDir, "rn-qa-overlay")
    check(directory.isDirectory || directory.mkdirs()) { "Could not create the attachment directory." }
    return File(directory, "${UUID.randomUUID()}.$suffix")
  }

  fun uri(context: Context, file: File): Uri = FileProvider.getUriForFile(context, "${context.packageName}.qaoverlay.files", file)

  fun importFile(context: Context, uri: Uri): File {
    val type = context.contentResolver.getType(uri) ?: "application/octet-stream"
    val suffix = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(type) ?: if (type.startsWith("video/")) "mp4" else "jpg"
    val target = newFile(context, suffix)
    try {
      context.contentResolver.openInputStream(uri).use { input ->
        requireNotNull(input) { "The selected file is no longer available." }
        target.outputStream().use { output ->
          val buffer = ByteArray(64 * 1024)
          var total = 0L
          while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            require(total <= MAX_BYTES) { "Choose a file smaller than 100 MB." }
            output.write(buffer, 0, count)
          }
        }
      }
      return target
    } catch (error: Exception) { target.delete(); throw error }
  }

  fun attachment(file: File, video: Boolean): QaAttachment {
    require(file.length() in 1..MAX_BYTES) { "Choose a non-empty file smaller than 100 MB." }
    val thumbnail = runCatching {
      if (video) {
        if (android.os.Build.VERSION.SDK_INT >= 29) ThumbnailUtils.createVideoThumbnail(file, Size(1024, 1024), null)
        else {
          @Suppress("DEPRECATION")
          ThumbnailUtils.createVideoThumbnail(file.path, android.provider.MediaStore.Video.Thumbnails.MINI_KIND)
        }
      }
      else {
        decodePreview(file, 1024)
      }
    }.getOrNull()
    return QaAttachment(file, video, thumbnail)
  }

  fun remove(attachment: QaAttachment) { attachments.remove(attachment); attachment.file.delete() }
  fun discard() {
    attachments.forEach { it.file.delete() }
    attachments.clear()
    title = ""
    description = ""
  }
}
