import Foundation
import Network
import os

@MainActor @Observable
final class Player: Identifiable {
    let name: String
    private(set) var state: PlayerState?
    private(set) var library: Library?
    private(set) var revision = 0
    private(set) var artwork: Artwork?

    private let endpoint: NWEndpoint
    private var connection: NWConnection?
    private var isCancelled = false
    private var artworkFrame: Int?

    nonisolated var id: String { name }

    init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
        connect()
    }

    func send(_ command: Command) {
        let context = NWConnection.ContentContext(identifier: "command", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection?.send(content: command.data, contentContext: context, completion: .idempotent)
    }

    func cancel() {
        isCancelled = true
        connection?.cancel()
    }

    func reconnect() {
        guard !isCancelled else { return }
        connection?.cancel()
        connect()
    }

    private func connect() {
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let self, connection === self.connection else { return }
                switch state {
                case .failed(let error), .waiting(let error): self.retry(after: error)
                default: break
                }
            }
        }
        self.connection = connection
        receive(on: connection)
        connection.start(queue: .main)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self, connection === self.connection else { return }
                if let error { return self.retry(after: error) }
                guard let data else { return self.receive(on: connection) }
                do {
                    switch try JSONDecoder().decode(Message.self, from: data) {
                    case .state(let state):
                        self.state = state
                        self.revision += 1
                        self.loadArtwork(state.frame ?? 0)
                    case .library(let library):
                        self.library = library
                    }
                } catch {
                    Logger().error("\(self.name): undecodable message: \(error)")
                }
                self.receive(on: connection)
            }
        }
    }

    private func loadArtwork(_ frame: Int) {
        guard frame != artworkFrame else { return }
        guard frame > 0 else {
            artworkFrame = frame
            return artwork = nil
        }
        guard let url = connection?.currentPath?.remoteEndpoint.flatMap(Self.frameURL) else { return }
        artworkFrame = frame
        Task {
            guard let artwork = await Artwork.load(from: url), frame == artworkFrame else { return }
            self.artwork = artwork
        }
    }

    /// The plugin's web server shares the host with the WebSocket and serves each window's frame by its port.
    private static func frameURL(_ endpoint: NWEndpoint) -> URL? {
        guard case let .hostPort(host, port) = endpoint else { return nil }
        let address = switch host {
        case .ipv4(let address): String("\(address)".prefix { $0 != "%" })
        case .ipv6(let address): "[\("\(address)".replacingOccurrences(of: "%", with: "%25"))]"
        case .name(let name, _): name
        @unknown default: ""
        }
        return URL(string: "http://\(address):8765/frame/\(port.rawValue).jpg")
    }

    private func retry(after error: NWError) {
        connection?.cancel()
        connection = nil
        state = nil
        guard !isCancelled else { return }
        Logger().info("\(self.name): reconnecting after \(error)")
        Task {
            try? await Task.sleep(for: .seconds(1))
            if !isCancelled, connection == nil { connect() }
        }
    }
}
