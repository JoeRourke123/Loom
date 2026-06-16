import UIKit

// Shared by any bridge that needs to present UI on the main thread.
@MainActor
func topViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
          let root = scene.keyWindow?.rootViewController else { return nil }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    return top
}
