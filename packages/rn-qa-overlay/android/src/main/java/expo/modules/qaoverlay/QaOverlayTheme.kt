package expo.modules.qaoverlay

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

@Composable
internal fun QaOverlayTheme(content: @Composable () -> Unit) {
  val dark = isSystemInDarkTheme()
  val context = LocalContext.current
  val colors = if (Build.VERSION.SDK_INT >= 31) {
    if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
  } else {
    if (dark) darkColorScheme() else expressiveLightColorScheme()
  }
  MaterialExpressiveTheme(colorScheme = colors, content = content)
}
