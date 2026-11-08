import ReplayKit
import SwiftUI
import UIKit

@MainActor
final class QaOverlayHost: NSObject, UIAdaptivePresentationControllerDelegate {
  static let shared = QaOverlayHost()
  let draft = QaDraft()
  private var bubble: QaFabWindow?
  private var panel: UIWindow?
  private let appearance = QaFabAppearance()
  private weak var previousKey: UIWindow?
  private var previousAccessibilityHidden = false
  private var hiddenHostViews: [(UIView, Bool)] = []
  private var timeout: Task<Void, Never>?
  private enum Recording { case idle, starting, active, stopping }
  private var recording = Recording.idle

  func install() {
    NotificationCenter.default.addObserver(self, selector: #selector(activate), name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    activate()
  }

  @objc private func activate() {
    guard bubble == nil,
      let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
    let window = QaFabWindow(appearance: appearance, windowScene: scene) { [weak self] in self?.pressed() }
    bubble = window
    window.setVisible(true, animated: !UIAccessibility.isReduceMotionEnabled)
  }

  @objc private func pressed() {
    switch recording {
    case .active: stopRecording()
    case .idle: open()
    case .starting, .stopping: break
    }
  }

  func open() {
    guard panel == nil, let scene = bubble?.windowScene else { return }
    bubble?.setVisible(false, animated: false)
    previousKey = scene.windows.first(where: { $0.isKeyWindow && $0 !== bubble })
    previousKey?.endEditing(true)
    previousAccessibilityHidden = previousKey?.accessibilityElementsHidden ?? false
    previousKey?.accessibilityElementsHidden = true
    hiddenHostViews = scene.windows.filter { $0 !== bubble }.compactMap { $0.rootViewController?.view }.map { ($0, $0.accessibilityElementsHidden) }
    hiddenHostViews.forEach { $0.0.accessibilityElementsHidden = true }
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 2
    window.backgroundColor = .clear
    let presenter = UIViewController()
    window.rootViewController = presenter
    window.rootViewController?.view.backgroundColor = .clear
    window.rootViewController?.view.accessibilityViewIsModal = true
    panel = window
    window.makeKeyAndVisible()
    let composer = UIHostingController(rootView: QaComposer(host: self, draft: draft, dismiss: { self.dismiss() }))
    composer.modalPresentationStyle = .formSheet
    composer.isModalInPresentation = true
    composer.sheetPresentationController?.detents = [.large()]
    composer.sheetPresentationController?.prefersGrabberVisible = false
    composer.presentationController?.delegate = self
    presenter.present(composer, animated: true)
  }

  private func dismiss() {
    panel?.rootViewController?.dismiss(animated: true) { self.close() }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    close()
  }

  func close() {
    panel?.isHidden = true
    panel?.rootViewController = nil
    panel = nil
    previousKey?.accessibilityElementsHidden = previousAccessibilityHidden
    hiddenHostViews.forEach { $0.0.accessibilityElementsHidden = $0.1 }
    hiddenHostViews = []
    previousKey?.makeKey()
    previousKey = nil
    bubble?.setVisible(true, animated: !UIAccessibility.isReduceMotionEnabled)
  }

  func startRecording() {
    #if targetEnvironment(simulator)
    // shortcut: Simulator ReplayKit exports no movie here; remove when a simulator passes export validation.
    draft.error = "Test screen recording on a physical iPhone. ReplayKit movie export is unavailable in this Simulator build."
    return
    #else
    guard recording == .idle else { return }
    let recorder = RPScreenRecorder.shared()
    guard recorder.isAvailable else { draft.error = "Screen recording is unavailable on this device."; return }
    recording = .starting
    close()
    appearance.recording = true
    appearance.enabled = false
    appearance.label = "…"
    appearance.accessibilityLabel = "Starting screen recording"
    recorder.isMicrophoneEnabled = false
    recorder.startRecording { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        if let error {
          self.recording = .idle
          self.resetButton()
          self.draft.error = error.localizedDescription
          self.open()
          return
        }
        self.recording = .active
        self.appearance.enabled = true
        self.appearance.label = "Stop"
        self.appearance.symbol = "stop.fill"
        self.appearance.accessibilityLabel = "Stop screen recording"
        self.timeout = Task { [weak self] in
          try? await Task.sleep(for: .seconds(60))
          guard !Task.isCancelled else { return }
          self?.stopRecording()
        }
      }
    }
    #endif
  }

  private func stopRecording() {
    guard recording == .active else { return }
    recording = .stopping
    timeout?.cancel()
    appearance.enabled = false
    appearance.label = "…"
    appearance.accessibilityLabel = "Finishing screen recording"
    do {
      let url = try QaDraft.newFile(extension: "mp4")
      RPScreenRecorder.shared().stopRecording(withOutput: url) { [weak self] error in
        Task { @MainActor in
          guard let self else { return }
          self.recording = .idle
          self.resetButton()
          if let error {
            try? FileManager.default.removeItem(at: url)
            self.draft.error = error.localizedDescription
          } else { self.draft.addOwnedFile(url, video: true) }
          self.open()
        }
      }
    } catch {
      RPScreenRecorder.shared().discardRecording { }
      recording = .idle
      resetButton()
      draft.error = error.localizedDescription
      open()
    }
  }

  private func resetButton() {
    appearance.symbol = "ladybug.fill"
    appearance.label = "Report"
    appearance.accessibilityLabel = "Report bug"
    appearance.recording = false
    appearance.enabled = true
  }

  @objc private func background() {
    if recording == .active { stopRecording() }
  }
}
