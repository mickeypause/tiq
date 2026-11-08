import CoreGraphics

@main struct PlacementChecks {
  static func main() {
    let bounds = CGSize(width: 402, height: 874)
    let safe = QaFabInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    let painted = CGRect(x: 10, y: 8, width: 52, height: 78)
    let ranges = QaFabPlacement.ranges(bounds: bounds, safeArea: safe, drawnFrame: painted, inset: 10)
    for x in [ranges.x.lowerBound, ranges.x.upperBound] {
      for y in [ranges.y.lowerBound, ranges.y.upperBound] {
        let actual = painted.offsetBy(dx: x, dy: y)
        assert(actual.minX >= 10 && actual.maxX <= bounds.width - 10)
        assert(actual.minY >= safe.top && actual.maxY <= bounds.height - safe.bottom)
      }
    }
    print("FAB painted bounds remain inside safe areas on all four edges")
  }
}
