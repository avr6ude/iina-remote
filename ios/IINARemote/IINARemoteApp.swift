import SwiftUI

@main
struct IINARemoteApp: App {
    init() {
        WatchRelay.shared.activate()
        Remote.shared.followSelected()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
