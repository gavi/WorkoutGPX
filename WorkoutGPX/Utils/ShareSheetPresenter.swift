import UIKit

// Presents the system share sheet from the topmost view controller. Used instead of a
// SwiftUI sheet because the share sheet inside a SwiftUI sheet mis-sizes on iPad and
// occasionally refuses to present a second time. `completion` receives true when the
// user finished an activity (AirDrop sent, file saved…) and false when they dismissed it.
func presentShareSheet(items: [Any], completion: ((Bool) -> Void)? = nil) {
    guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? windowScene.windows.first?.rootViewController else {
        completion?(false)
        return
    }
    
    var topController = rootViewController
    while let presented = topController.presentedViewController {
        topController = presented
    }
    
    let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
    activityViewController.completionWithItemsHandler = { _, finished, _, _ in
        completion?(finished)
    }
    
    // iPad presents this as a popover and needs an anchor
    if let popover = activityViewController.popoverPresentationController {
        popover.sourceView = topController.view
        popover.sourceRect = CGRect(x: topController.view.bounds.midX,
                                    y: topController.view.bounds.midY,
                                    width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
    
    topController.present(activityViewController, animated: true)
}
