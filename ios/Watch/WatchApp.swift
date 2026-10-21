import SwiftUI
import WatchConnectivity

@main
struct WatchApp: App {
    var body: some Scene {
        WindowGroup {
            NowPlayingView()
        }
    }
}

/// Talks to the iPhone app, which owns the connection to IINA; watchOS apps can't reach the Mac directly.
@MainActor @Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    private(set) var state: PlayerState?
    private(set) var isUnreachable = false

    override init() {
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh() { request(["refresh": true]) }

    func send(_ command: Command) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        request(["command": data])
    }

    private func request(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(message) { @Sendable reply in
            let state = (reply["state"] as? Data).flatMap { try? JSONDecoder().decode(PlayerState.self, from: $0) }
            Task { @MainActor in
                self.state = state
                self.isUnreachable = state == nil
            }
        } errorHandler: { @Sendable _ in
            Task { @MainActor in self.isUnreachable = true }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.refresh() }
    }
}

struct NowPlayingView: View {
    @State private var link = PhoneLink()
    @State private var volume = 0.0

    var body: some View {
        Group {
            if let state = link.state, !state.title.isEmpty {
                controls(state)
            } else {
                ContentUnavailableView {
                    Label(link.state == nil ? "Open IINA Remote on iPhone" : "Nothing playing", systemImage: "play.tv")
                } actions: {
                    Button("Retry") { link.refresh() }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                link.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func controls(_ state: PlayerState) -> some View {
        VStack(spacing: 8) {
            Text(state.host).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            Text(state.title).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            ProgressView(value: state.duration > 0 ? state.time / state.duration : 0).tint(.red)
            HStack {
                Button("Back 10 Seconds", systemImage: "gobackward.10") { link.send(.seek(-10, absolute: false)) }
                Button(state.pause ? "Play" : "Pause", systemImage: state.pause ? "play.fill" : "pause.fill") { link.send(.set(.pause, !state.pause)) }
                Button("Forward 30 Seconds", systemImage: "goforward.30") { link.send(.seek(30, absolute: false)) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
        }
        .focusable()
        .digitalCrownRotation($volume, from: 0, through: max(state.volumeMax, 1), by: 5, sensitivity: .medium)
        .onAppear { volume = state.volume }
        .onChange(of: volume) { _, newValue in
            if abs(newValue - state.volume) >= 1 { link.send(.set(.volume, newValue.rounded())) }
        }
    }
}
