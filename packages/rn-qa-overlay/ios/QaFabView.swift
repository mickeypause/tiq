// Copyright 2015-present 650 Industries. All rights reserved.

#if !os(macOS) && !os(tvOS)

import SwiftUI
import ExpoModulesCore

enum QaFabConstants {
  static let iconSize: CGFloat = 44
  static let margin: CGFloat = 10
  static let verticalPadding: CGFloat = 0
  static let dragThreshold: CGFloat = 10
  static let momentumFactor: CGFloat = 0.35
  static let labelDismissDelay: TimeInterval = 10
  static let idleTimeout: UInt64 = 5_000_000_000
  static let imageSize: CGFloat = 26

  static let snapAnimation: Animation = .spring(
    response: 0.6,
    dampingFraction: 0.7,
    blendDuration: 0
  )
}

struct QaFabPillHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = QaFabConstants.iconSize

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

@MainActor
final class QaFabAppearance: ObservableObject {
  @Published var symbol = "ladybug.fill"
  @Published var label = "Report"
  @Published var accessibilityLabel = "Report bug"
  @Published var recording = false
  @Published var enabled = true
}

struct QaFabPill: View {
  @ObservedObject var appearance: QaFabAppearance
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var isPressed: Bool
  @Binding var isDragging: Bool
  @State private var showLabel = true
  @State private var isIdle = false
  @State private var idleTask: Task<Void, Never>?

  private var isInteracting: Bool {
    isPressed || isDragging
  }

  var body: some View {
    VStack(spacing: 8) {
      actionButton
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isPressed)
        .onChange(of: isInteracting) { interacting in
          if interacting {
            idleTask?.cancel()
            withAnimation {
              isIdle = false
            }
          } else {
            startIdleTimer()
          }
        }
        .onAppear {
          startIdleTimer()
        }

      if showLabel || appearance.recording {
        Text(appearance.label)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
          .fixedSize()
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.regularMaterial, in: Capsule())
          .transition(.opacity.combined(with: .scale(scale: 0.8)))
      }
    }
    .background(
      GeometryReader { proxy in
        Color.clear.preference(key: QaFabPillHeightKey.self, value: proxy.size.height)
      }
    )
    .onDisappear { idleTask?.cancel() }
    .saturation(isIdle && !appearance.recording ? 0 : 1)
    .opacity(isIdle && !appearance.recording ? 0.5 : 1)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isIdle)
    .task {
      // [Alan] This is poor practice but without it, the label is not included in the drag gesture
      // and remains in its original position.
      do { try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * QaFabConstants.labelDismissDelay)) }
      catch { return }
      await MainActor.run {
        withAnimation(.easeOut(duration: 0.3)) {
          showLabel = false
        }
      }
    }
  }

  private func startIdleTimer() {
    idleTask?.cancel()
    idleTask = Task {
      try? await Task.sleep(nanoseconds: QaFabConstants.idleTimeout)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        withAnimation {
          isIdle = true
        }
      }
    }
  }

  private var actionButton: some View {
    Image(systemName: appearance.symbol)
      .resizable()
      .frame(width: QaFabConstants.imageSize, height: QaFabConstants.imageSize)
      .foregroundStyle(.white)
      .frame(width: QaFabConstants.iconSize, height: QaFabConstants.iconSize)
      .background(Color.blue, in: Circle())
      .background(
        Circle()
          .stroke(Color.blue.opacity(0.5), lineWidth: 4)
          .frame(width: QaFabConstants.iconSize + 4, height: QaFabConstants.iconSize + 4)
      )
      .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
  }
}

struct QaFabView: View {
  @ObservedObject var appearance: QaFabAppearance
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let onOpenMenu: () -> Void
  let onFrameChange: (CGRect) -> Void

  private let fabSize = CGSize(width: 72, height: QaFabConstants.iconSize + 50)

  /// Centred in the touch frame, so its top moves as the label appears and dismisses.
  private var drawnFrame: CGRect {
    let ring = QaFabPlacement.ringOverhang
    let width = QaFabConstants.iconSize + ring * 2
    return CGRect(
      x: (fabSize.width - width) / 2,
      y: (fabSize.height - pillHeight) / 2 - ring,
      width: width,
      height: pillHeight + ring * 2
    )
  }

  // UserDefaults keys for persisting position
  private static let positionXKey = "TiqFAB.positionX"
  private static let positionYKey = "TiqFAB.positionY"
  private static let hasStoredPositionKey = "TiqFAB.hasStoredPosition"

  private static func loadStoredPosition() -> CGPoint? {
    guard UserDefaults.standard.bool(forKey: hasStoredPositionKey) else { return nil }
    let x = UserDefaults.standard.double(forKey: positionXKey)
    let y = UserDefaults.standard.double(forKey: positionYKey)
    return CGPoint(x: x, y: y)
  }

  private static func savePosition(_ position: CGPoint) {
    UserDefaults.standard.set(position.x, forKey: positionXKey)
    UserDefaults.standard.set(position.y, forKey: positionYKey)
    UserDefaults.standard.set(true, forKey: hasStoredPositionKey)
  }

  @State private var position: CGPoint = .zero
  @State private var isDragging = false
  @State private var isPressed = false
  @State private var dragStartPosition: CGPoint = .zero
  @State private var didPosition = false
  @State private var pillHeight: CGFloat = QaFabConstants.iconSize

  // Get safe area from window since .ignoresSafeArea() may zero out geometry values
  private var windowSafeArea: UIEdgeInsets {
    return SceneGeometry.keyWindow()?.safeAreaInsets ?? .zero
  }

  private let dragSpring: Animation = .spring(
    response: 0.25,
    dampingFraction: 0.85,
    blendDuration: 0
  )

  private var currentFrame: CGRect {
    CGRect(origin: position, size: fabSize)
  }

  var body: some View {
    GeometryReader { geometry in
      // Use window safe area - geometry values may be incorrect initially or due to .ignoresSafeArea()
      let safeArea = EdgeInsets(
        top: windowSafeArea.top,
        leading: windowSafeArea.left,
        bottom: windowSafeArea.bottom,
        trailing: windowSafeArea.right
      )

      QaFabPill(appearance: appearance, isPressed: $isPressed, isDragging: $isDragging)
        .frame(width: fabSize.width, height: fabSize.height)
        .onPreferenceChange(QaFabPillHeightKey.self) { height in
          pillHeight = height
          let ranges = placementRanges(bounds: geometry.size, safeArea: safeArea)
          let clamped = CGPoint(
            x: position.x.clamped(to: ranges.x),
            y: position.y.clamped(to: ranges.y)
          )
          guard clamped != position else { return }
          var transaction = Transaction()
          transaction.disablesAnimations = true
          withTransaction(transaction) {
            position = clamped
          }
          onFrameChange(CGRect(origin: clamped, size: fabSize))
        }
        .position(x: currentFrame.midX, y: currentFrame.midY)
        .gesture(dragGesture(bounds: geometry.size, safeArea: safeArea))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.accessibilityLabel)
        .accessibilityIdentifier("qa-overlay.button")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if appearance.enabled { onOpenMenu() } }
        .onAppear {
          placeInitially(bounds: geometry.size, safeArea: safeArea)
        }
        .onChange(of: geometry.size) { newSize in
          let newPos = snapToEdge(
            from: position,
            velocity: .zero,
            bounds: newSize,
            safeArea: safeArea
          )
          position = newPos
          onFrameChange(CGRect(origin: newPos, size: fabSize))
        }
        .animation(didPosition && !reduceMotion ? (isDragging ? dragSpring : QaFabConstants.snapAnimation) : nil, value: position)
    }
    .ignoresSafeArea()
  }

  private func dragGesture(bounds: CGSize, safeArea: EdgeInsets) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if !isPressed {
          isPressed = true
        }
        if !isDragging && value.translation.magnitude > QaFabConstants.dragThreshold {
          isDragging = true
          isPressed = false
          dragStartPosition = position
        }
        if isDragging {
          let rawX = dragStartPosition.x + value.translation.width
          let rawY = dragStartPosition.y + value.translation.height

          position = CGPoint(x: rawX, y: rawY)
          onFrameChange(currentFrame)
        }
      }
      .onEnded { value in
        isPressed = false
        let dragDistance = value.translation.magnitude

        if dragDistance < QaFabConstants.dragThreshold {
          isDragging = false
          if appearance.enabled { onOpenMenu() }
        } else {
          let velocity = CGPoint(
            x: value.predictedEndLocation.x - value.location.x,
            y: value.predictedEndLocation.y - value.location.y
          )

          let newPos = snapToEdge(
            from: position,
            velocity: velocity,
            bounds: bounds,
            safeArea: safeArea
          )

          DispatchQueue.main.async {
            isDragging = false
            position = newPos
            Self.savePosition(newPos)
            onFrameChange(CGRect(origin: newPos, size: fabSize))
          }
        }
      }
  }

  private func placeInitially(bounds: CGSize, safeArea: EdgeInsets) {
    let initialPos: CGPoint
    if let storedPos = Self.loadStoredPosition() {
      let ranges = placementRanges(bounds: bounds, safeArea: safeArea)
      initialPos = CGPoint(
        x: storedPos.x.clamped(to: ranges.x),
        y: storedPos.y.clamped(to: ranges.y)
      )
    } else {
      initialPos = defaultPosition(bounds: bounds, safeArea: safeArea)
    }
    position = initialPos
    onFrameChange(CGRect(origin: initialPos, size: fabSize))
    // Enable position animations only after the initial placement so the
    // button appears at its final spot instead of sliding in from (0, 0).
    DispatchQueue.main.async {
      didPosition = true
    }
  }

  private func placementRanges(
    bounds: CGSize,
    safeArea: EdgeInsets
  ) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
    let ranges = QaFabPlacement.ranges(
      bounds: bounds,
      safeArea: QaFabInsets(
        top: safeArea.top,
        leading: safeArea.leading,
        bottom: safeArea.bottom,
        trailing: safeArea.trailing
      ),
      drawnFrame: drawnFrame,
      inset: QaFabConstants.margin
    )
    return (ranges.x, ranges.y)
  }

  private func defaultPosition(bounds: CGSize, safeArea: EdgeInsets) -> CGPoint {
    let ranges = placementRanges(bounds: bounds, safeArea: safeArea)
    return CGPoint(x: ranges.x.upperBound, y: ranges.y.lowerBound)
  }

  private func snapToEdge(
    from point: CGPoint,
    velocity: CGPoint,
    bounds: CGSize,
    safeArea: EdgeInsets
  ) -> CGPoint {
    let momentumX = velocity.x * QaFabConstants.momentumFactor
    let momentumY = velocity.y * QaFabConstants.momentumFactor
    let ranges = placementRanges(bounds: bounds, safeArea: safeArea)

    let estimatedCenterX = point.x + self.fabSize.width / 2 + momentumX
    let targetX = estimatedCenterX < bounds.width / 2 ? ranges.x.lowerBound : ranges.x.upperBound
    let targetY = (point.y + momentumY).clamped(to: ranges.y)

    return CGPoint(x: targetX, y: targetY)
  }
}

private extension CGSize {
  var magnitude: CGFloat {
    sqrt(width * width + height * height)
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

#endif
