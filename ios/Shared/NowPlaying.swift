import ActivityKit
import Foundation
import WidgetKit

/// What the widget and Live Activity show.
struct NowPlaying: Codable, Hashable {
    let mac: String
    let title: String
    let chapter: String?
    let isPlaying: Bool
    let time: Double
    let duration: Double
    let tint: Tint?
    let date: Date

    @MainActor init(_ player: Player, state: PlayerState, date: Date = .now) {
        self.mac = player.name
        self.title = state.title
        self.chapter = state.chapter.flatMap { index in
            player.library?.chapters.indices.contains(index) == true ? player.library?.chapters[index].title : nil
        }.flatMap { $0.isEmpty ? nil : $0 }
        self.isPlaying = !state.pause
        self.time = state.time
        self.duration = state.duration
        self.tint = player.artwork?.tint
        self.date = date
    }

    /// The Mac and, when the file has them, the chapter.
    var subtitle: String { [mac, chapter].compactMap(\.self).joined(separator: " · ") }

    /// The span the progress bar animates over without further updates.
    var interval: ClosedRange<Date> {
        let start = date.addingTimeInterval(-time)
        return start...start.addingTimeInterval(max(duration, time + 1))
    }

    var fraction: Double { duration > 0 ? min(1, time / duration) : 0 }

    /// Asks the network for what's playing right now and its frame: the widget has no other way to learn them.
    @MainActor static func fetch() async -> (NowPlaying, Artwork?)? {
        let discovery = Remote.shared.discovery
        for _ in 0..<80 {
            let ready = discovery.players.filter { $0.state != nil }
            if let player = ready.first(where: { !($0.state?.title.isEmpty ?? true) }) ?? (ready.count == discovery.players.count ? ready.first : nil),
               let state = player.state {
                for _ in 0..<60 where ((state.frame ?? 0) > 0 && player.artwork == nil) || player.library == nil {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                return (NowPlaying(player, state: player.state ?? state), player.artwork)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }
}

struct PlaybackAttributes: ActivityAttributes {
    typealias ContentState = NowPlaying
}

extension NowPlaying {
    /// True when `other` shows the same thing this would show now, i.e. nothing but the clock has moved.
    func matches(_ other: NowPlaying) -> Bool {
        let expected = time + (isPlaying ? other.date.timeIntervalSince(date) : 0)
        return mac == other.mac && title == other.title && chapter == other.chapter && isPlaying == other.isPlaying
            && duration == other.duration && tint == other.tint && abs(expected - other.time) < 2
    }
}

extension Remote {
    /// Moves the widget and Live Activity along with `state`; nothing playing ends the activity.
    /// iOS only lets an app start a Live Activity from the foreground, so callers pass `canStart` only then.
    func publish(_ state: PlayerState, canStart: Bool = false) {
        guard let selected else { return }
        let nowPlaying = NowPlaying(selected, state: state)
        let activities = Activity<PlaybackAttributes>.activities
        if let published, published.matches(nowPlaying), !(canStart && activities.isEmpty) { return }
        published = nowPlaying
        WidgetCenter.shared.reloadAllTimelines()

        let content = ActivityContent(state: nowPlaying, staleDate: nil)
        let ends = state.title.isEmpty
        Task {
            for activity in Activity<PlaybackAttributes>.activities {
                if ends {
                    await activity.end(content, dismissalPolicy: .immediate)
                } else {
                    await activity.update(content)
                }
            }
        }
        if canStart, activities.isEmpty, !state.title.isEmpty, !state.pause,
           ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: PlaybackAttributes(), content: content)
        }
    }
}
