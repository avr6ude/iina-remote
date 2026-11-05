import Foundation
import Observation

@MainActor @Observable
final class Remote {
    static let shared = Remote()
    static let selectionKey = "selectedPlayer"
    static let liveActivityKey = "liveActivity"

    let discovery = Discovery()
    @ObservationIgnored var published: NowPlaying?
    @ObservationIgnored var isAwaitingConnection = false

    private init() {
        UserDefaults.standard.register(defaults: [Self.liveActivityKey: true])
    }

    var selectedName: String {
        get { access(keyPath: \.selectedName); return UserDefaults.standard.string(forKey: Self.selectionKey) ?? "" }
        set { withMutation(keyPath: \.selectedName) { UserDefaults.standard.set(newValue, forKey: Self.selectionKey) } }
    }

    var selected: Player? {
        let players = discovery.players
        return players.first { $0.name == selectedName } ?? (players.count == 1 ? players.first : nil)
    }

    /// Sends `command` to the selected IINA once it is connected and returns the state that follows,
    /// or nil when no IINA answers within a few seconds (e.g. the app was just launched in the background).
    func perform(_ command: Command) async -> PlayerState? {
        guard let player = await connectedPlayer() else { return nil }
        let revision = player.revision
        player.send(command)
        for _ in 0..<20 where player.revision == revision {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return player.state
    }

    func connectedPlayer() async -> Player? {
        for _ in 0..<60 {
            if let player = selected, player.state != nil { return player }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// The selected IINA as it is now. iOS may have frozen the app since the last message, leaving a dead connection and an old
    /// state, so like `NowPlaying.fetch` this only counts a state that arrives after reconnecting.
    func reconnectedPlayer() async -> Player? {
        let stale = selected.map { ($0.name, $0.revision) }
        discovery.refresh()
        for _ in 0..<100 {
            if let player = selected, player.state != nil, player.name != stale?.0 || player.revision != stale?.1 { return player }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }
}
