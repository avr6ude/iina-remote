import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RemoteWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        PlaybackLiveActivity()
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowPlaying", provider: Provider()) { entry in
            NowPlayingView(nowPlaying: entry.nowPlaying)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("Control what's playing in IINA.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Entry: TimelineEntry {
        let date = Date.now
        let nowPlaying: NowPlaying?
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(nowPlaying: nil) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(nowPlaying: .load())) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(nowPlaying: .load())], policy: .never))
        }
    }
}

private struct NowPlayingView: View {
    let nowPlaying: NowPlaying?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(nowPlaying?.mac ?? "IINA Remote")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(title)
                .font(.headline)
                .lineLimit(family == .systemSmall ? 3 : 2)
            Spacer(minLength: 0)
            if let nowPlaying, !nowPlaying.title.isEmpty {
                ProgressView(value: nowPlaying.fraction).tint(.red)
                Controls(isPlaying: nowPlaying.isPlaying, compact: family == .systemSmall)
            }
        }
    }

    private var title: String {
        guard let nowPlaying else { return "Open the app to connect to IINA" }
        return nowPlaying.title.isEmpty ? "Nothing playing" : nowPlaying.title
    }
}

private struct Controls: View {
    let isPlaying: Bool
    let compact: Bool

    var body: some View {
        HStack {
            if !compact {
                Button(intent: SkipBackIntent()) { Image(systemName: "gobackward.10") }
                Spacer()
            }
            Button(intent: TogglePlaybackIntent()) { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
            Spacer()
            Button(intent: SkipForwardIntent()) { Image(systemName: "goforward.30") }
            if !compact {
                Spacer()
                Button(intent: NextItemIntent()) { Image(systemName: "forward.end.fill") }
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
    }
}

struct PlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.mac).font(.caption).foregroundStyle(.secondary)
                        Text(context.state.title).font(.headline).lineLimit(1)
                    }
                    Spacer()
                    Controls(isPlaying: context.state.isPlaying, compact: true)
                        .frame(width: 96)
                }
                Progress(nowPlaying: context.state)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "play.tv.fill").foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.mac).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Progress(nowPlaying: context.state)
                        HStack {
                            Button(intent: SkipBackIntent()) { Image(systemName: "gobackward.10") }
                            Spacer()
                            Button(intent: TogglePlaybackIntent()) { Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill") }
                            Spacer()
                            Button(intent: SkipForwardIntent()) { Image(systemName: "goforward.30") }
                        }
                        .font(.title2)
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill").foregroundStyle(.red)
            } compactTrailing: {
                if context.state.isPlaying {
                    Text(timerInterval: context.state.interval, countsDown: false).monospacedDigit().frame(maxWidth: 48)
                }
            } minimal: {
                Image(systemName: "play.tv.fill").foregroundStyle(.red)
            }
        }
    }
}

private struct Progress: View {
    let nowPlaying: NowPlaying

    var body: some View {
        if nowPlaying.isPlaying {
            ProgressView(timerInterval: nowPlaying.interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(.red)
        } else {
            ProgressView(value: nowPlaying.fraction).tint(.red)
        }
    }
}
