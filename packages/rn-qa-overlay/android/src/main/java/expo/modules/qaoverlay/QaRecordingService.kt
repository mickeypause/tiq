package expo.modules.qaoverlay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.io.File

class QaRecordingService : Service() {
  companion object { const val STOP = "expo.modules.qaoverlay.STOP" }
  private var projection: MediaProjection? = null
  private var display: VirtualDisplay? = null
  private var recorder: MediaRecorder? = null
  private var file: File? = null
  private var started = false
  private var finishing = false
  private val handler = Handler(Looper.getMainLooper())
  private val timeout = Runnable { finishRecording() }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == STOP) { finishRecording(); return START_NOT_STICKY }
    if (started || finishing) return START_NOT_STICKY
    try {
      val channel = "qa-overlay-recording"
      if (Build.VERSION.SDK_INT >= 26) getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(channel, "QA screen recording", NotificationManager.IMPORTANCE_LOW))
      val stop = PendingIntent.getService(this, 0, Intent(this, QaRecordingService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
      @Suppress("DEPRECATION")
      val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
      val notification = builder
        .setSmallIcon(android.R.drawable.presence_video_online).setContentTitle("Recording QA evidence")
        .setContentText("Tap Stop to attach the recording. Maximum 60 seconds.").setOngoing(true)
        .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
      if (Build.VERSION.SDK_INT >= 29) startForeground(2401, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
      else startForeground(2401, notification)

      @Suppress("DEPRECATION")
      val data = intent?.getParcelableExtra<Intent>("data") ?: error("Screen capture consent was not supplied.")
      val result = intent.getIntExtra("resultCode", 0)
      val output = QaDraft.newFile(this, "mp4")
      file = output
      val metrics = resources.displayMetrics
      val factor = minOf(1f, 1280f / maxOf(metrics.widthPixels, metrics.heightPixels))
      val width = ((metrics.widthPixels * factor).toInt() / 2) * 2
      val height = ((metrics.heightPixels * factor).toInt() / 2) * 2
      @Suppress("DEPRECATION")
      val mediaRecorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else MediaRecorder()
      recorder = mediaRecorder
      mediaRecorder.apply {
        setVideoSource(MediaRecorder.VideoSource.SURFACE)
        setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        setVideoSize(width, height)
        setVideoFrameRate(30)
        setVideoEncodingBitRate(4_000_000)
        setMaxFileSize(QaDraft.MAX_BYTES)
        setOnInfoListener { _, what, _ -> if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) finishRecording() }
        setOnErrorListener { _, _, _ -> QaDraft.error = "Screen recording was interrupted."; finishRecording() }
        setOutputFile(output.absolutePath)
        prepare()
      }
      val capture = requireNotNull(getSystemService(MediaProjectionManager::class.java).getMediaProjection(result, data)) { "Screen capture consent is no longer valid." }
      projection = capture
      capture.registerCallback(object : MediaProjection.Callback() {
        override fun onStop() { finishRecording() }
      }, handler)
      display = capture.createVirtualDisplay("QA evidence", width, height, metrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, mediaRecorder.surface, null, handler)
      mediaRecorder.start()
      started = true
      QaDraft.recording = true
      handler.postDelayed(timeout, 60_000)
    } catch (error: Exception) {
      QaDraft.error = "Could not start screen recording: ${error.message}"
      finishRecording()
    }
    return START_NOT_STICKY
  }

  private fun finishRecording() {
    if (finishing) return
    finishing = true
    handler.removeCallbacks(timeout)
    var valid = false
    try { if (started) { recorder?.stop(); valid = true } }
    catch (_: Exception) { QaDraft.error = "The recording could not be finalized. Try recording for a little longer." }
    finally {
      started = false
      display?.release(); display = null
      projection?.stop(); projection = null
      recorder?.release(); recorder = null
    }
    val output = file
    if (output != null) {
      if (valid) {
        try { QaDraft.attachments.add(QaDraft.attachment(output, true)) }
        catch (error: Exception) { output.delete(); QaDraft.error = error.message }
      } else output.delete()
    }
    file = null
    QaDraft.recording = false
    QaOverlayHost.returnToDraft()
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  override fun onDestroy() {
    if (!finishing) finishRecording()
    super.onDestroy()
  }
}
