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
        // The extension can outlive a refresh with its connections frozen, so only states that arrive after reconnecting count.
        let stale = Dictionary(uniqueKeysWithValues: discovery.players.map { ($0.name, $0.revision) })
        discovery.refresh()
        for _ in 0..<80 {
            let ready = discovery.players.filter { $0.state != nil && $0.revision != stale[$0.name] }
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
    /// Keeps the widget and Live Activity on the selected IINA for as long as the app runs. A view's onChange can't:
    /// it stops firing in the background, and an intent launches the app without any views.
    func followSelected() {
        withObservationTracking {
            _ = selected?.state
            _ = selected?.artwork?.tint
        } onChange: {
            Task { @MainActor in self.followSelected() }
        }
        Task { await publish() }
    }

    /// Moves the widget and Live Activity along with the selected IINA; nothing playing, no connection, or the setting turned off ends the activity.
    func publish() async {
        guard let selected, let state = selected.state else { return await endIfDisconnected() }
        let nowPlaying = NowPlaying(selected, state: state)
        let changed = published?.matches(nowPlaying) != true
        if changed {
            published = nowPlaying
            WidgetCenter.shared.reloadAllTimelines()
        }

        let activities = Activity<PlaybackAttributes>.activities
        let content = ActivityContent(state: nowPlaying, staleDate: nil)
        if state.title.isEmpty || !UserDefaults.standard.bool(forKey: Self.liveActivityKey) {
            await endLiveActivity()
        } else if activities.isEmpty {
            // iOS only lets an app start a Live Activity from the foreground; in the background this throws.
            if !state.pause, ActivityAuthorizationInfo().areActivitiesEnabled {
                _ = try? Activity.request(attributes: PlaybackAttributes(), content: content)
            }
        } else if changed {
            for activity in activities { await activity.update(content) }
        }
    }

    func endLiveActivity() async {
        for activity in Activity<PlaybackAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Connections drop whenever the phone wakes, and an activity ended in the background can't come back until the app opens,
    /// so this gives the connection ten seconds to return. Short sleeps keep time frozen in the background from counting.
    private func endIfDisconnected() async {
        guard !isAwaitingConnection else { return }
        isAwaitingConnection = true
        defer { isAwaitingConnection = false }
        for _ in 0..<40 where selected?.state == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard selected?.state == nil else { return }
        await endLiveActivity()
        if published != nil {
            published = nil
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
