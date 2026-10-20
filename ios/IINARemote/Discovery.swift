import Network
import Observation

@MainActor @Observable
final class Discovery {
    private(set) var players: [Player] = []
    private(set) var isDenied = false

    private let browser = NWBrowser(for: .bonjour(type: "_iina-remote._tcp", domain: nil), using: .tcp)

    init() {
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))) = state {
                    self?.isDenied = true
                } else if case .ready = state {
                    self?.isDenied = false
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        browser.start(queue: .main)
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: NWEndpoint] = [:]
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint { found[name] = result.endpoint }
        }
        for player in players where found[player.name] == nil { player.cancel() }
        let kept = players.filter { found[$0.name] != nil }
        let added = found.filter { name, _ in !kept.contains { $0.name == name } }.map { Player(name: $0.key, endpoint: $0.value) }
        players = (kept + added).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
