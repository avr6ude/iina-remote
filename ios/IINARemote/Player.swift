import Foundation
import Network
import os

@MainActor @Observable
final class Player: Identifiable {
    let name: String
    private(set) var state: PlayerState?

    private let endpoint: NWEndpoint
    private var connection: NWConnection?
    private var isCancelled = false

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
                    self.state = try JSONDecoder().decode(PlayerState.self, from: data)
                } catch {
                    Logger().error("\(self.name): undecodable state: \(error)")
                }
                self.receive(on: connection)
            }
        }
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

struct PlayerState: Decodable, Equatable {
    struct Track: Decodable, Equatable, Identifiable {
        enum Kind: String, Decodable { case audio, sub }

        let id: Int
        let type: Kind
        let title: String
        let lang: String

        var label: String {
            let parts = [title, lang.uppercased()].filter { !$0.isEmpty }
            return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
        }
    }

    let title: String
    let pause: Bool
    let time: Double
    let duration: Double
    let volume: Double
    let volumeMax: Double
    let mute: Bool
    let speed: Double
    let sid: String
    let aid: String
    let subVisible: Bool
    let subDelay: Double
    let audioDelay: Double
    let tracks: [Track]
}

enum Command {
    enum Property: String {
        case pause, volume, mute, sid, aid, speed
        case subDelay = "sub-delay"
        case audioDelay = "audio-delay"
        case subVisibility = "sub-visibility"
    }

    case set(Property, String)
    case seek(Double, absolute: Bool)
    case previous
    case next

    static func set(_ property: Property, _ value: Bool) -> Command { .set(property, value ? "yes" : "no") }
    static func set(_ property: Property, _ value: Double) -> Command { .set(property, String(value)) }

    var data: Data {
        let message: [String: Any] = switch self {
        case let .set(property, value): ["set": property.rawValue, "value": value]
        case let .seek(seconds, absolute): ["cmd": "seek", "args": [String(seconds), absolute ? "absolute" : "relative"]]
        case .previous: ["cmd": "playlist-prev"]
        case .next: ["cmd": "playlist-next"]
        }
        return try! JSONSerialization.data(withJSONObject: message)
    }
}
