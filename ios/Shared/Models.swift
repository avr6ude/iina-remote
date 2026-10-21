import Foundation

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

    let host: String
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
    let chapter: Int?
    let playlistPos: Int?
    let tracks: [Track]
}

struct Library: Decodable, Equatable {
    struct Item: Decodable, Equatable {
        let title: String
        let current: Bool
    }

    struct Chapter: Decodable, Equatable {
        let title: String
        let start: Double
    }

    struct Recent: Decodable, Equatable, Identifiable {
        let title: String
        let url: String
        let progress: Double
        let duration: Double

        var id: String { url }
        var fraction: Double { duration > 0 ? min(1, progress / duration) : 0 }
    }

    let playlist: [Item]
    let chapters: [Chapter]
    let recent: [Recent]
}

enum Message: Decodable {
    case state(PlayerState)
    case library(Library)

    private enum Kind: String, Decodable { case state, library }
    private enum Keys: CodingKey { case kind }

    init(from decoder: any Decoder) throws {
        switch try decoder.container(keyedBy: Keys.self).decode(Kind.self, forKey: .kind) {
        case .state: self = .state(try PlayerState(from: decoder))
        case .library: self = .library(try Library(from: decoder))
        }
    }
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
    case playItem(Int)
    case playChapter(Int)
    case openRecent(String)

    static func set(_ property: Property, _ value: Bool) -> Command { .set(property, value ? "yes" : "no") }
    static func set(_ property: Property, _ value: Double) -> Command { .set(property, String(value)) }

    var data: Data {
        let message: [String: Any] = switch self {
        case let .set(property, value): ["set": property.rawValue, "value": value]
        case let .seek(seconds, absolute): ["cmd": "seek", "args": [String(seconds), absolute ? "absolute" : "relative"]]
        case .previous: ["cmd": "playlist-prev"]
        case .next: ["cmd": "playlist-next"]
        case let .playItem(index): ["cmd": "playlist-play-index", "args": [index]]
        case let .playChapter(index): ["cmd": "chapter", "args": [index]]
        case let .openRecent(url): ["cmd": "open-recent", "args": [url]]
        }
        return try! JSONSerialization.data(withJSONObject: message)
    }
}
