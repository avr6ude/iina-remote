import Network
import Observation

@MainActor @Observable
final class Discovery {
    private(set) var players: [Player] = []
    private(set) var isDenied = false

    private var browser: NWBrowser?

    init() {
        startBrowsing()
    }

    func refresh() {
        browser?.cancel()
        startBrowsing()
        players.forEach { $0.reconnect() }
    }

    private func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: "_iina-remote._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            MainActor.assumeIsolated {
                guard let self, browser === self.browser else { return }
                switch state {
                case .ready:
                    self.isDenied = false
                case .waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))):
                    self.isDenied = true
                case .failed:
                    self.refresh()
                default:
                    break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            MainActor.assumeIsolated {
                guard let self, browser === self.browser else { return }
                self.update(results)
            }
        }
        self.browser = browser
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
