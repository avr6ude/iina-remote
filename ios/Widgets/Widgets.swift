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
            NowPlayingView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Control what's playing in IINA.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Entry: TimelineEntry {
        let date = Date.now
        let nowPlaying: NowPlaying?
        var artwork: UIImage?
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(nowPlaying: nil) }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            nonisolated(unsafe) let completion = completion
            Task { @MainActor in completion(await Self.entry()) }
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            nonisolated(unsafe) let completion = completion
            Task { @MainActor in
                completion(Timeline(entries: [await Self.entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
            }
        }

        @MainActor private static func entry() async -> Entry {
            guard let (nowPlaying, artwork) = await NowPlaying.fetch() else { return Entry(nowPlaying: nil) }
            // Widgets refuse images much larger than they are.
            let image = artwork.flatMap { artwork in
                let scale = min(1, 640 / max(artwork.image.size.width, artwork.image.size.height))
                return artwork.image.preparingThumbnail(of: CGSize(width: artwork.image.size.width * scale, height: artwork.image.size.height * scale))
            }
            return Entry(nowPlaying: nowPlaying, artwork: image)
        }
    }
}

private struct NowPlayingView: View {
    let entry: NowPlayingWidget.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let nowPlaying = entry.nowPlaying, !nowPlaying.title.isEmpty {
                if family == .systemSmall { small(nowPlaying) } else { medium(nowPlaying) }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: "play.tv.fill").font(.title2).foregroundStyle(.red)
                    Spacer(minLength: 0)
                    Text("Nothing Playing").font(.subheadline.weight(.semibold))
                    Text(entry.nowPlaying?.mac ?? "Open a video in IINA").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var background: some View {
        if let artwork = entry.artwork, entry.nowPlaying?.title.isEmpty == false {
            if family == .systemSmall {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .overlay(LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            } else {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .overlay((entry.nowPlaying?.tint?.color ?? .black).opacity(0.55))
            }
        } else {
            LinearGradient(colors: [entry.nowPlaying?.tint?.color ?? Color(white: 0.2), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
        }
    }

    private func small(_ nowPlaying: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Remaining(nowPlaying: nowPlaying).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                PlayButton(isPlaying: nowPlaying.isPlaying, size: 38)
            }
            Spacer(minLength: 0)
            Text(nowPlaying.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(nowPlaying.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Progress(nowPlaying: nowPlaying).padding(.top, 6)
        }
    }

    private func medium(_ nowPlaying: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let artwork = entry.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 112, height: 63)
                        .clipShape(.rect(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(nowPlaying.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 8)
            Progress(nowPlaying: nowPlaying)
            Spacer(minLength: 8)
            Controls(nowPlaying: nowPlaying, playSize: 38).font(.title3)
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
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(.white, in: .circle)
        }
        .buttonStyle(.plain)
    }
}

private struct Controls: View {
    let nowPlaying: NowPlaying
    let playSize: CGFloat

    var body: some View {
        HStack {
            Button(intent: PreviousItemIntent()) { Image(systemName: "backward.end.fill") }
            Spacer()
            Button(intent: SkipBackIntent()) { Image(systemName: "gobackward.10") }
            Spacer()
            PlayButton(isPlaying: nowPlaying.isPlaying, size: playSize)
            Spacer()
            Button(intent: SkipForwardIntent()) { Image(systemName: "goforward.30") }
            Spacer()
            Button(intent: NextItemIntent()) { Image(systemName: "forward.end.fill") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

struct PlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackAttributes.self) { context in
            PlaybackCard(nowPlaying: context.state)
                .padding(16)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(context.state.tint?.color ?? .black.opacity(0.7))
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

/// The lock screen player.
private struct PlaybackCard: View {
    let nowPlaying: NowPlaying

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title).font(.headline).lineLimit(1)
                    Text(nowPlaying.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.tv.fill").foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Progress(nowPlaying: nowPlaying)
                HStack {
                    Time(nowPlaying: nowPlaying, remaining: false)
                    Spacer()
                    Time(nowPlaying: nowPlaying, remaining: true)
                }
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Controls(nowPlaying: nowPlaying, playSize: 44)
                .font(.title2)
                .padding(.horizontal, 8)
        }
    }
}

private struct Remaining: View {
    let nowPlaying: NowPlaying

    var body: some View {
        if nowPlaying.isPlaying {
            Text("-\(Text(timerInterval: nowPlaying.interval, countsDown: true))")
        } else {
            Text("Paused")
        }
    }
}

private struct Time: View {
    let nowPlaying: NowPlaying
    let remaining: Bool

    var body: some View {
        if nowPlaying.isPlaying {
            let timer = Text(timerInterval: nowPlaying.interval, countsDown: remaining)
            Text(remaining ? "-\(timer)" : "\(timer)").multilineTextAlignment(remaining ? .trailing : .leading)
        } else {
            let seconds = remaining ? nowPlaying.duration - nowPlaying.time : nowPlaying.time
            Text((remaining ? "-" : "") + Duration.seconds(max(0, seconds).rounded(.down))
                .formatted(.time(pattern: nowPlaying.duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        }
    }
}

private struct Progress: View {
    let nowPlaying: NowPlaying

    var body: some View {
        Group {
            if nowPlaying.isPlaying {
                ProgressView(timerInterval: nowPlaying.interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: nowPlaying.fraction)
            }
        }
        .tint(.white)
    }
}
