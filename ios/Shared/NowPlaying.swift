import ActivityKit
import Foundation
import WidgetKit

/// What the widget and Live Activity show: the last state the app saw, shared through the App Group.
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

    private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.avrdude.iina-remote") }
    private static let key = "nowPlaying"

    static func load() -> NowPlaying? {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(NowPlaying.self, from: $0) }
    }

    func save() {
        Self.defaults?.set(try? JSONEncoder().encode(self), forKey: Self.key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct PlaybackAttributes: ActivityAttributes {
    typealias ContentState = NowPlaying
}

extension Remote {
    /// Saves `state` for the widget and moves the Live Activity along with it; nothing playing ends the activity.
    func publish(_ state: PlayerState, startActivity: Bool = false) {
        guard let mac = selected?.name else { return }
        let nowPlaying = NowPlaying(mac: mac, state: state)
        nowPlaying.save()

        let content = ActivityContent(state: nowPlaying, staleDate: nil)
        let hasActivity = !Activity<PlaybackAttributes>.activities.isEmpty
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
        if startActivity, !hasActivity, !state.title.isEmpty, !state.pause,
           ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: PlaybackAttributes(), content: content)
        }
    }
}
