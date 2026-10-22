import SwiftUI

@main
struct IINARemoteApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        WatchRelay.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Only iPhone Duo's inner display has room for the player in landscape, which its tabletop pose needs.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let bounds = window?.windowScene?.screen.bounds else { return .portrait }
        return min(bounds.width, bounds.height) > 600 ? .allButUpsideDown : .portrait
    }
}
