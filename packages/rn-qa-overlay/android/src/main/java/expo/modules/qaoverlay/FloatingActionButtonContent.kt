// Adapted from expo-dev-menu. Copyright 2015-present 650 Industries. MIT; see THIRD_PARTY_NOTICES.md.
package expo.modules.qaoverlay

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Text

private val FabBlue = Color(0xFF007AFF)

@Composable
fun FloatingActionButtonContent(
  modifier: Modifier = Modifier,
  isPressed: Boolean = false,
  isDragging: Boolean = false,
  isIdle: Boolean = false,
  showLabel: Boolean = true
) {
  val scale by animateFloatAsState(
    targetValue = if (isPressed && !isDragging) {
      0.9f
    } else {
      1f
    },
    label = "pressScale"
  )

  val idleAlpha by animateFloatAsState(
    targetValue = if (isIdle && !QaDraft.recording) {
      0.5f
    } else {
      1f
    },
    label = "idleAlpha"
  )

  val idleSaturation by animateFloatAsState(
    targetValue = if (isIdle && !QaDraft.recording) {
      0f
    } else {
      1f
    },
    label = "idleSaturation"
  )

  Column(
    horizontalAlignment = Alignment.CenterHorizontally,
    modifier = modifier
      .scale(scale)
      .graphicsLayer {
        alpha = idleAlpha
      }
      .drawWithContent {
        val colorMatrix = android.graphics.ColorMatrix()
        colorMatrix.setSaturation(idleSaturation)
        val paint = android.graphics.Paint().apply {
          colorFilter = android.graphics.ColorMatrixColorFilter(colorMatrix)
        }
        drawContext.canvas.nativeCanvas.saveLayer(null, paint)
        drawContent()
        drawContext.canvas.nativeCanvas.restore()
      }
  ) {
    Box(
      contentAlignment = Alignment.Center,
      modifier = Modifier
        .shadow(
          elevation = 8.dp,
          shape = CircleShape,
          ambientColor = Color.Black.copy(alpha = 0.4f),
          spotColor = Color.Black.copy(alpha = 0.4f)
        )
        .size(52.dp)
        .border(4.dp, FabBlue.copy(alpha = 0.3f), CircleShape)
        .padding(4.dp)
        .background(FabBlue, CircleShape)
    ) {
      Icon(
        imageVector = if (QaDraft.recording) Icons.Filled.Stop else Icons.Filled.BugReport,
        contentDescription = null,
        tint = Color.White,
        modifier = Modifier.size(26.dp)
      )
    }

    AnimatedVisibility(
      visible = showLabel || QaDraft.recording,
      exit = fadeOut() + scaleOut()
    ) {
      Box(
        modifier = Modifier
          .wrapContentWidth(unbounded = true)
          .padding(top = 6.dp)
          .shadow(4.dp, RoundedCornerShape(percent = 50))
          .background(Color.White, RoundedCornerShape(percent = 50))
          .padding(horizontal = 10.dp, vertical = 4.dp)
      ) {
        Text(
          text = if (QaDraft.recording) "Stop" else "Report",
          color = Color.Black,
          fontSize = 11.sp,
          lineHeight = 13.sp,
          fontWeight = FontWeight.SemiBold
        )
      }
    }
  }
}
