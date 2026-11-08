package expo.modules.qaoverlay

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun QaAttachmentGallery(initial: QaAttachment, onClose: () -> Unit) {
  val attachments = QaDraft.attachments.toList()
  if (attachments.isEmpty()) { LaunchedEffect(Unit) { onClose() }; return }
  val pager = androidx.compose.foundation.pager.rememberPagerState(
    initialPage = attachments.indexOfFirst { it.file == initial.file }.coerceAtLeast(0),
    pageCount = { QaDraft.attachments.size }
  )
  var menu by remember { mutableStateOf(false) }
  androidx.compose.ui.window.Dialog(onDismissRequest = onClose,
    properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
    Scaffold(
      modifier = Modifier.fillMaxSize().testTag("qa-overlay.preview"),
      containerColor = androidx.compose.ui.graphics.Color.Black,
      contentColor = androidx.compose.ui.graphics.Color.White,
      topBar = {
        CenterAlignedTopAppBar(title = {}, colors = TopAppBarDefaults.topAppBarColors(
          containerColor = androidx.compose.ui.graphics.Color.Black,
          navigationIconContentColor = androidx.compose.ui.graphics.Color.White,
          actionIconContentColor = androidx.compose.ui.graphics.Color.White),
          navigationIcon = {
            IconButton(onClick = onClose, modifier = Modifier.testTag("qa-overlay.preview.close")) {
              Icon(Icons.AutoMirrored.Outlined.ArrowBack, "Back")
            }
          }, actions = {
            Box {
              IconButton(onClick = { menu = true }, modifier = Modifier.testTag("qa-overlay.preview.more")) {
                Icon(Icons.Outlined.MoreHoriz, "More")
              }
              DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Remove") }, leadingIcon = { Icon(Icons.Outlined.Delete, null) },
                  enabled = !QaLinearSession.locked, onClick = {
                    menu = false
                    attachments.getOrNull(pager.currentPage)?.let { QaDraft.remove(it) }
                    if (QaDraft.attachments.isEmpty()) onClose()
                  })
              }
            }
          })
      }
    ) { insets ->
      androidx.compose.foundation.pager.HorizontalPager(
        state = pager, key = { attachments[it].file.path }, modifier = Modifier.fillMaxSize().padding(insets)
      ) { page ->
        QaAssetPage(attachments[page], active = pager.currentPage == page && !pager.isScrollInProgress)
      }
    }
  }
}

@Composable
private fun QaAssetPage(attachment: QaAttachment, active: Boolean) {
  val context = LocalContext.current
  val isActive by rememberUpdatedState(active)
  var error by remember(attachment.file) { mutableStateOf<String?>(null) }
  val image by produceState<Bitmap?>(null, attachment.file) {
    if (!attachment.video) {
      try { value = withContext(Dispatchers.IO) { decodePreview(attachment.file) } }
      catch (_: Exception) { error = "This image could not be opened." }
    }
  }
  var video by remember { mutableStateOf<VideoView?>(null) }
  val lifecycle = LocalLifecycleOwner.current.lifecycle
  DisposableEffect(lifecycle) {
    val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) video?.pause() }
    lifecycle.addObserver(observer)
    onDispose { video?.stopPlayback(); lifecycle.removeObserver(observer) }
  }
  LaunchedEffect(active) { if (active) video?.start() else video?.pause() }
  Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    if (error != null) Text(error!!, Modifier.padding(24.dp))
    else if (attachment.video) {
      AndroidView(factory = { VideoView(it).apply {
        video = this
        setMediaController(MediaController(it).also { controls -> controls.setAnchorView(this) })
        setOnErrorListener { _, _, _ -> error = "This video could not be played."; true }
        setOnPreparedListener { if (isActive) start() }
        setVideoURI(QaDraft.uri(context, attachment.file))
      } }, modifier = Modifier.fillMaxSize(), onRelease = { it.stopPlayback(); video = null })
    } else {
      val bitmap = image
      if (bitmap != null) Image(bitmap.asImageBitmap(), "Image", Modifier.fillMaxSize(),
        filterQuality = androidx.compose.ui.graphics.FilterQuality.High)
      else CircularProgressIndicator()
    }
  }
}

internal fun decodePreview(file: File, maxSize: Int = 4096): Bitmap {
  if (Build.VERSION.SDK_INT >= 28) {
    return ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
      val scale = minOf(1f, maxSize.toFloat() / maxOf(info.size.width, info.size.height))
      decoder.setTargetSize(maxOf(1, (info.size.width * scale).toInt()), maxOf(1, (info.size.height * scale).toInt()))
    }
  }
  val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
  BitmapFactory.decodeFile(file.path, options)
  options.inSampleSize = 1
  while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > maxSize) options.inSampleSize *= 2
  options.inJustDecodeBounds = false
  val bitmap = requireNotNull(BitmapFactory.decodeFile(file.path, options))
  val orientation = runCatching { ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
  val matrix = Matrix().apply {
    when (orientation) {
      ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
      ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
      ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
      ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
      ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
      ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(270f); postScale(-1f, 1f) }
      ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(270f)
    }
  }
  if (matrix.isIdentity) return bitmap
  return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true).also { if (it !== bitmap) bitmap.recycle() }
}
