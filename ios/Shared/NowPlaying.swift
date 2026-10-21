import ActivityKit
import Foundation
import WidgetKit

/// What the widget and Live Activity show.
struct NowPlaying: Codable, Hashable {
    let mac: String
    let title: String
    let isPlaying: Bool
    let time: Double
    let duration: Double
    let date: Date

    init(mac: String, state: PlayerState, date: Date = .now) {
        self.mac = mac
        self.title = state.title
        self.isPlaying = !state.pause
        self.time = state.time
        self.duration = state.duration
        self.date = date
    }

    /// The span the progress bar animates over without further updates.
    var interval: ClosedRange<Date> {
        let start = date.addingTimeInterval(-time)
        return start...start.addingTimeInterval(max(duration, time + 1))
    }

    var fraction: Double { duration > 0 ? min(1, time / duration) : 0 }

    /// Asks the network for what's playing right now: the widget has no other way to learn it.
    @MainActor static func fetch() async -> NowPlaying? {
        let discovery = Remote.shared.discovery
        for _ in 0..<80 {
            let ready = discovery.players.filter { $0.state != nil }
            if let player = ready.first(where: { !($0.state?.title.isEmpty ?? true) }) ?? (ready.count == discovery.players.count ? ready.first : nil),
               let state = player.state {
                return NowPlaying(mac: player.name, state: state)
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
        return mac == other.mac && title == other.title && isPlaying == other.isPlaying
            && duration == other.duration && abs(expected - other.time) < 2
    }
}

extension Remote {
    /// Moves the widget and Live Activity along with `state`; nothing playing ends the activity.
    /// iOS only lets an app start a Live Activity from the foreground, so callers pass `canStart` only then.
    func publish(_ state: PlayerState, canStart: Bool = false) {
        guard let mac = selected?.name else { return }
        let nowPlaying = NowPlaying(mac: mac, state: state)
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
