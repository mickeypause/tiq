package expo.modules.qaoverlay

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class QaLinearCallbackActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val address = intent.dataString
    lifecycleScope.launch {
      if (address != null) QaLinearSession.callback(this@QaLinearCallbackActivity, address)
      startActivity(Intent(this@QaLinearCallbackActivity, QaOverlayActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
      finish()
    }
  }
}
