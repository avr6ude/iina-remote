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
                .containerBackground(for: .widget) { Brand.gradient }
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

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            nonisolated(unsafe) let completion = completion
            Task { @MainActor in completion(Entry(nowPlaying: await NowPlaying.fetch())) }
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            nonisolated(unsafe) let completion = completion
            Task { @MainActor in
                let entry = Entry(nowPlaying: await NowPlaying.fetch())
                completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
            }
        }
    }
}

private enum Brand {
    static let gradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.33, blue: 0.35), Color(red: 0.6, green: 0.09, blue: 0.15)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let deep = Color(red: 0.75, green: 0.15, blue: 0.2)
}

private struct NowPlayingView: View {
    let nowPlaying: NowPlaying?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let nowPlaying, !nowPlaying.title.isEmpty {
                if family == .systemSmall { small(nowPlaying) } else { medium(nowPlaying) }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Artwork(size: 44)
                    Spacer(minLength: 0)
                    Text("Nothing playing").font(.headline)
                    Text(nowPlaying?.mac ?? "Open a video in IINA").font(.caption).opacity(0.75).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
    }

    private func small(_ nowPlaying: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Artwork(size: 44)
                Spacer()
                PlayButton(isPlaying: nowPlaying.isPlaying, size: 44)
            }
            Spacer(minLength: 0)
            Text(nowPlaying.title).font(.headline).lineLimit(2)
            Text(nowPlaying.mac).font(.caption).opacity(0.75).lineLimit(1)
            Progress(nowPlaying: nowPlaying, tint: .white).padding(.top, 4)
        }
    }

    private func medium(_ nowPlaying: NowPlaying) -> some View {
        HStack(spacing: 14) {
            Artwork(size: 118)
            VStack(alignment: .leading, spacing: 4) {
                Text(nowPlaying.mac).font(.caption).opacity(0.75).lineLimit(1)
                Text(nowPlaying.title).font(.headline).lineLimit(2)
                Spacer(minLength: 0)
                Progress(nowPlaying: nowPlaying, tint: .white)
                HStack {
                    Button(intent: SkipBackIntent()) { Image(systemName: "gobackward.10") }
                    Spacer()
                    PlayButton(isPlaying: nowPlaying.isPlaying, size: 36)
                    Spacer()
                    Button(intent: SkipForwardIntent()) { Image(systemName: "goforward.30") }
                    Spacer()
                    Button(intent: NextItemIntent()) { Image(systemName: "forward.end.fill") }
                }
                .font(.title3)
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
}

private struct Artwork: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(.white.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "play.tv.fill").font(.system(size: size * 0.42)).foregroundStyle(.white)
            }
    }
}

private struct PlayButton: View {
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Brand.deep)
                .frame(width: size, height: size)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct PlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackAttributes.self) { context in
            PlaybackCard(nowPlaying: context.state)
                .padding(16)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    PlaybackCard(nowPlaying: context.state).padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: "play.tv.fill").foregroundStyle(.red)
            } compactTrailing: {
                if context.state.isPlaying {
                    Text(timerInterval: context.state.interval, countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 44)
                } else {
                    Image(systemName: "pause.fill")
                }
            } minimal: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill").foregroundStyle(.red)
            }
        }
    }
}

private struct PlaybackCard: View {
    let nowPlaying: NowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title).font(.headline).lineLimit(1)
                Text(nowPlaying.mac).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            VStack(spacing: 4) {
                Progress(nowPlaying: nowPlaying)
                HStack {
                    Time(nowPlaying: nowPlaying, remaining: false)
                    Spacer()
                    Time(nowPlaying: nowPlaying, remaining: true)
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            HStack {
                Button(intent: SkipBackIntent()) { Image(systemName: "gobackward.10") }
                Spacer()
                Button(intent: TogglePlaybackIntent()) { Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill") }
                Spacer()
                Button(intent: SkipForwardIntent()) { Image(systemName: "goforward.30") }
                Spacer()
                Button(intent: NextItemIntent()) { Image(systemName: "forward.end.fill") }
            }
            .font(.title2)
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
    }
}

private struct Time: View {
    let nowPlaying: NowPlaying
    let remaining: Bool

    var body: some View {
        if nowPlaying.isPlaying {
            Text(timerInterval: nowPlaying.interval, countsDown: remaining)
                .multilineTextAlignment(remaining ? .trailing : .leading)
        } else {
            let seconds = remaining ? nowPlaying.duration - nowPlaying.time : nowPlaying.time
            Text((remaining ? "-" : "") + Duration.seconds(max(0, seconds).rounded(.down))
                .formatted(.time(pattern: nowPlaying.duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        }
    }
}

private struct Progress: View {
    let nowPlaying: NowPlaying
    var tint: Color = .red

    var body: some View {
        if nowPlaying.isPlaying {
            ProgressView(timerInterval: nowPlaying.interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(tint)
        } else {
            ProgressView(value: nowPlaying.fraction).tint(tint)
        }
    }
}
