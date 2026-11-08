package expo.modules.qaoverlay

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import expo.modules.core.interfaces.Package
import expo.modules.core.interfaces.ReactActivityLifecycleListener

class QaOverlayPackage : Package {
  override fun createReactActivityLifecycleListeners(activityContext: Context): List<ReactActivityLifecycleListener> {
    return listOf(object : ReactActivityLifecycleListener {
      override fun onResume(activity: Activity) {
        // Expo creates this listener before the Activity's base context is attached.
        val metadata = activity.packageManager.getApplicationInfo(activity.packageName, PackageManager.GET_META_DATA).metaData
        if (metadata?.getBoolean("expo.modules.qaoverlay.ENABLED", false) == true) QaOverlayHost.attach(activity)
      }
      override fun onDestroy(activity: Activity) { QaOverlayHost.detach(activity) }
    })
  }
}
