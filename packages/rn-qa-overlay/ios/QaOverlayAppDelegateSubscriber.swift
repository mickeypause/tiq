import ExpoModulesCore
import UIKit

public final class QaOverlayAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    guard Bundle.main.object(forInfoDictionaryKey: "RnQaOverlayEnabled") as? Bool == true else { return true }
    Task { @MainActor in QaOverlayHost.shared.install() }
    return true
  }
}
