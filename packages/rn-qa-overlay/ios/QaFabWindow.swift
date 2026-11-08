// Copyright 2015-present 650 Industries. All rights reserved.

#if !os(macOS) && !os(tvOS)

import Combine
import ExpoModulesCore
import UIKit
import SwiftUI

/// A passthrough window that hosts the floating action button.
class QaFabWindow: UIWindow {
  private let appearance: QaFabAppearance
  private let onPress: () -> Void
  private var hostingController: UIHostingController<QaFabView>?
  private let accessibleButton = QaFabTouchThroughButton(frame: .zero)
  private var appearanceObservation: AnyCancellable?
  var fabFrame: CGRect = .zero {
    didSet { accessibleButton.frame = fabFrame }
  }
  private var currentAnimator: UIViewPropertyAnimator?
  private var targetVisibility: Bool?

  init(appearance: QaFabAppearance, windowScene: UIWindowScene, onPress: @escaping () -> Void) {
    self.appearance = appearance
    self.onPress = onPress
    super.init(windowScene: windowScene)
    setupWindow()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupWindow() {
    windowLevel = .alert + 3
    frame = windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
    backgroundColor = .clear
    isHidden = true
    alpha = 0

    let fabView = QaFabView(
      appearance: appearance,
      onOpenMenu: { [weak self] in
        self?.onPress()
      },
      onFrameChange: { [weak self] frame in
        self?.fabFrame = frame
      }
    )

    let hostingController = UIHostingController(rootView: fabView)
    hostingController.view.backgroundColor = .clear
    self.hostingController = hostingController
    let container = UIViewController()
    container.view.backgroundColor = .clear
    container.addChild(hostingController)
    hostingController.view.frame = container.view.bounds
    hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hostingController.view.accessibilityElementsHidden = true
    container.view.addSubview(hostingController.view)
    hostingController.didMove(toParent: container)
    accessibleButton.accessibilityIdentifier = "qa-overlay.button"
    accessibleButton.addAction(UIAction { [weak self] _ in self?.onPress() }, for: .touchUpInside)
    container.view.addSubview(accessibleButton)
    rootViewController = container
    updateAccessibility()
    appearanceObservation = appearance.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.updateAccessibility()
    }
  }

  private func updateAccessibility() {
    accessibleButton.accessibilityLabel = appearance.accessibilityLabel
    accessibleButton.isEnabled = appearance.enabled
  }

  private var edgeTranslation: CGAffineTransform {
    let availableWidth = SceneGeometry.bounds(for: self).width
    let isOnRight = fabFrame == .zero || fabFrame.midX > (availableWidth / 2)
    let dx: CGFloat = isOnRight ? 60 : -60
    return CGAffineTransform(translationX: dx, y: 0)
  }

  func setVisible(_ visible: Bool, animated: Bool = true) {
    // Skip if already animating to the same state
    if targetVisibility == visible {
      return
    }

    // Cancel any in-progress animation and reset to clean state
    if currentAnimator != nil {
      currentAnimator?.stopAnimation(true)
      currentAnimator = nil
      transform = .identity
    }

    targetVisibility = visible

    if visible {
      isHidden = false
      alpha = 0
      transform = edgeTranslation

      let animator = UIViewPropertyAnimator(duration: animated ? 0.5 : 0, dampingRatio: 0.6) {
        self.alpha = 1
        self.transform = .identity
      }
      animator.addCompletion { [weak self] _ in
        self?.targetVisibility = nil
      }
      currentAnimator = animator
      animator.startAnimation()
    } else {
      let animator = UIViewPropertyAnimator(duration: animated ? 0.3 : 0, dampingRatio: 0.8) {
        self.alpha = 0
        self.transform = self.edgeTranslation
      }
      animator.addCompletion { [weak self] position in
        self?.targetVisibility = nil
        if position == .end {
          self?.isHidden = true
          self?.transform = .identity
        }
      }
      currentAnimator = animator
      animator.startAnimation()
    }
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hitArea = fabFrame.insetBy(dx: -10, dy: -10)
    if hitArea.contains(point) {
      return super.hitTest(point, with: event)
    }

    return nil
  }
}

// Expose a native accessible button while letting SwiftUI handle the physical drag/tap gesture.
private final class QaFabTouchThroughButton: UIButton {
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
}

#endif
