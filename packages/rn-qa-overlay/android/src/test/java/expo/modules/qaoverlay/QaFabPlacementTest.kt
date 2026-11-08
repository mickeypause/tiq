package expo.modules.qaoverlay

import androidx.compose.ui.geometry.Offset
import org.junit.Assert.*
import org.junit.Test

class QaFabPlacementTest {
  @Test fun snapsToBothEdgesAndKeepsVerticalMomentumInsideBounds() {
    val bounds = Offset(300f, 600f)
    assertEquals(Offset(0f, 100f), calculateTargetPosition(Offset(10f, 100f), ExpoVelocityTracker.PointF(0f, 0f), bounds, 84f))
    assertEquals(Offset(300f, 100f), calculateTargetPosition(Offset(280f, 100f), ExpoVelocityTracker.PointF(0f, 0f), bounds, 84f))
    assertEquals(Offset(300f, 600f), calculateTargetPosition(Offset(10f, 500f), ExpoVelocityTracker.PointF(4000f, 4000f), bounds, 84f))
    assertEquals(Offset(0f, 0f), calculateTargetPosition(Offset(280f, 100f), ExpoVelocityTracker.PointF(-4000f, -4000f), bounds, 84f))
  }
}
