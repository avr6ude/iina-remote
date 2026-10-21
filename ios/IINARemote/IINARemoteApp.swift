import SwiftUI

@main
struct IINARemoteApp: App {
    init() {
        WatchRelay.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
