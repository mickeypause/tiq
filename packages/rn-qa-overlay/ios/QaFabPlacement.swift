// Copyright 2015-present 650 Industries. All rights reserved.

import CoreGraphics

struct QaFabInsets {
  let top: CGFloat
  let leading: CGFloat
  let bottom: CGFloat
  let trailing: CGFloat
}

struct QaFabPlacementRanges {
  let x: ClosedRange<CGFloat>
  let y: ClosedRange<CGFloat>
}

enum QaFabPlacement {
  /// The ring is stroked on a path 4pt wider than the icon, so it paints this far outside it.
  static let ringOverhang: CGFloat = 4

  /// Origins the FAB frame may take, given the painted pill in that frame's coordinate space.
  static func ranges(
    bounds: CGSize,
    safeArea: QaFabInsets,
    drawnFrame: CGRect,
    inset: CGFloat
  ) -> QaFabPlacementRanges {
    // Keep `inset` from each edge, but never sit further in than the safe area already requires.
    let minX = max(safeArea.leading, inset) - drawnFrame.minX
    let maxX = bounds.width - max(safeArea.trailing, inset) - drawnFrame.maxX
    let minY = max(safeArea.top, inset) - drawnFrame.minY
    let maxY = bounds.height - max(safeArea.bottom, inset) - drawnFrame.maxY

    return QaFabPlacementRanges(
      x: min(minX, maxX)...max(minX, maxX),
      y: min(minY, maxY)...max(minY, maxY)
    )
  }
}
