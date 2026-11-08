package expo.modules.qaoverlay

import android.app.Activity
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.ui.platform.ComposeView
import java.lang.ref.WeakReference

object QaOverlayHost {
  private const val LABEL_DURATION_MILLIS = 10_000L
  private var firstShownAt: Long? = null
  private var host = WeakReference<Activity>(null)
  private var bubble: ComposeView? = null
  val labelRemainingMillis: Long get() = (LABEL_DURATION_MILLIS - (SystemClock.uptimeMillis() - (firstShownAt ?: SystemClock.uptimeMillis()))).coerceAtLeast(0)

  fun attach(activity: Activity) {
    if (host.get() === activity && bubble?.parent != null) {
      bubble?.visibility = View.VISIBLE
      return
    }
    host.get()?.let { detach(it) }
    host = WeakReference(activity)
    val root = activity.window.decorView as? ViewGroup ?: return
    bubble = addButton(activity, root)
  }

  fun hideButton() { bubble?.visibility = View.GONE }

  private fun addButton(activity: Activity, root: ViewGroup): ComposeView {
    if (firstShownAt == null) firstShownAt = SystemClock.uptimeMillis()
    return ComposeView(activity).also { view ->
      // Do not consume the host's keyboard/system insets or intercept touches outside the FAB.
      view.consumeWindowInsets = false
      view.setContent {
        QaOverlayTheme {
          MovableFloatingActionButton(onPress = {
            if (QaDraft.recording) stop(activity)
            else if (activity !is QaOverlayActivity) {
              hideButton()
              activity.startActivity(Intent(activity, QaOverlayActivity::class.java))
            }
          })
        }
      }
      root.addView(view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }
  }

  private fun removeButton(view: ComposeView) {
    view.disposeComposition()
    (view.parent as? ViewGroup)?.removeView(view)
  }

  fun detach(activity: Activity) {
    if (host.get() !== activity) return
    bubble?.let { removeButton(it) }
    bubble = null
    host.clear()
  }

  private fun stop(activity: Activity) {
    activity.startService(Intent(activity, QaRecordingService::class.java).setAction(QaRecordingService.STOP))
  }

  fun returnToDraft() {
    host.get()?.let { it.startActivity(Intent(it, QaOverlayActivity::class.java)) }
  }
}
