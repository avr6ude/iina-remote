import SwiftUI

struct RemoteView: View {
    let player: Player

    @AppStorage(Remote.liveActivityKey) private var showsLiveActivity = false

    var body: some View {
        Group {
            if let state = player.state, !state.title.isEmpty {
                NowPlayingScreen(player: player, state: state)
            } else if player.state != nil {
                Idle(recent: player.library?.recent ?? [], send: player.send)
            } else {
                ProgressView("Connecting…")
            }
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu("More", systemImage: "ellipsis") {
                Toggle("Live Activity", systemImage: "platter.filled.bottom.iphone", isOn: $showsLiveActivity)
            }
        }
    }
}

private enum Panel: String, Identifiable {
    case subtitles = "Subtitles"
    case audio = "Audio"
    case library = "Up Next"

    var id: Self { self }
}

private struct NowPlayingScreen: View {
    let player: Player
    let state: PlayerState

    @State private var panel: Panel?

    private static let speeds = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            if let artwork = player.artwork {
                Image(uiImage: artwork.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                    .frame(maxHeight: 340)
                    .scaleEffect(state.pause ? 0.86 : 1)
                    .animation(.spring(duration: 0.5, bounce: 0.3), value: state.pause)
                Spacer(minLength: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title).font(.title3.weight(.semibold)).lineLimit(2)
                if let subtitle { Text(subtitle).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Scrubber(state: state, send: player.send).padding(.top, 18)
            transport.padding(.vertical, 24)
            Volume(state: state, send: player.send)
            Spacer(minLength: 24)
            bottomBar
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .background { Backdrop(artwork: player.artwork) }
        .preferredColorScheme(.dark)
        .sheet(item: $panel) { panel in
            PanelSheet(panel: panel, player: player).presentationDetents([.medium, .large])
        }
    }

    private var hasPlaylist: Bool { (player.library?.playlist.count ?? 0) > 1 }

    private var subtitle: String? {
        if let library = player.library, let index = state.chapter, library.chapters.indices.contains(index) {
            let title = library.chapters[index].title
            return title.isEmpty ? "Chapter \(index + 1)" : title
        }
        if hasPlaylist, let library = player.library, let position = state.playlistPos {
            return "\(position + 1) of \(library.playlist.count)"
        }
        return nil
    }

    private var transport: some View {
        HStack {
            Button("Previous", systemImage: "backward.end.fill") { player.send(.previous) }
                .font(.title2)
                .disabled(!hasPlaylist)
            Spacer()
            Button("Back 10 Seconds", systemImage: "gobackward.10") { player.send(.seek(-10, absolute: false)) }
                .font(.title)
            Spacer()
            Button(state.pause ? "Play" : "Pause", systemImage: state.pause ? "play.fill" : "pause.fill") {
                player.send(.set(.pause, !state.pause))
            }
            .font(.system(size: 50))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 72, height: 72)
            Spacer()
            Button("Forward 30 Seconds", systemImage: "goforward.30") { player.send(.seek(30, absolute: false)) }
                .font(.title)
            Spacer()
            Button("Next", systemImage: "forward.end.fill") { player.send(.next) }
                .font(.title2)
                .disabled(!hasPlaylist)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(PressStyle())
    }

    private var bottomBar: some View {
        HStack {
            panelButton(.subtitles, state.sid != "no" && state.subVisible ? "captions.bubble.fill" : "captions.bubble")
            Spacer()
            panelButton(.audio, "waveform")
            Spacer()
            Menu {
                Picker("Speed", selection: Binding(get: { state.speed }, set: { player.send(.set(.speed, $0)) })) {
                    ForEach(Self.speeds, id: \.self) { Text("\($0.formatted())×").tag($0) }
                }
            } label: {
                Text("\(state.speed.formatted())×")
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 44, minHeight: 32)
            }
            .accessibilityLabel("Speed")
            Spacer()
            panelButton(.library, "list.bullet")
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .labelStyle(.iconOnly)
        .buttonStyle(PressStyle())
        .padding(.horizontal, 8)
    }

    private func panelButton(_ panel: Panel, _ symbol: String) -> some View {
        Button(panel.rawValue, systemImage: symbol) { self.panel = panel }
    }
}

/// The artwork blurred into the background, like Music's player.
private struct Backdrop: View {
    let artwork: Artwork?

    var body: some View {
        ZStack {
            Color.black
            if let artwork {
                Image(uiImage: artwork.image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .overlay(artwork.tint.color.opacity(0.45))
                    .overlay(.black.opacity(0.25))
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: artwork?.tint)
        .ignoresSafeArea()
    }
}

private struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0), in: .circle)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A thin track that thickens while dragged; the drag moves the value relative to where it started, as in Music.
private struct Bar: View {
    let value: Double
    let range: ClosedRange<Double>
    @Binding var dragging: Double?
    var onEnded: (Double) -> Void = { _ in }

    @State private var start = 0.0

    var body: some View {
        GeometryReader { geometry in
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let fraction = min(max(((dragging ?? value) - range.lowerBound) / span, 0), 1)
            Capsule()
                .fill(.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(dragging == nil ? 0.7 : 1)).frame(width: geometry.size.width * fraction)
                }
                .clipShape(.capsule)
                .frame(height: dragging == nil ? 7 : 14)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragging == nil { start = value }
                        let moved = start + drag.translation.width / geometry.size.width * span
                        dragging = min(max(moved, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        if let dragging { onEnded(dragging) }
                        dragging = nil
                    })
        }
        .frame(height: 28)
        .animation(.spring(duration: 0.3), value: dragging == nil)
    }
}

private struct Scrubber: View {
    let state: PlayerState
    let send: (Command) -> Void

    @State private var dragging: Double?
    @State private var target: Double?

    var body: some View {
        let duration = max(state.duration, 1)
        let time = min(dragging ?? target ?? state.time, duration)
        VStack(spacing: 0) {
            Bar(value: target ?? state.time, range: 0...duration, dragging: $dragging) { time in
                send(.seek(time, absolute: true))
                target = time
            }
            HStack {
                Text(clock(time, of: duration))
                Spacer()
                Text("-" + clock(duration - time, of: duration))
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .task(id: target) {
            try? await Task.sleep(for: .seconds(1))
            target = nil
        }
    }
}

private struct Volume: View {
    let state: PlayerState
    let send: (Command) -> Void

    @State private var dragging: Double?

    var body: some View {
        HStack(spacing: 12) {
            Button(state.mute ? "Unmute" : "Mute", systemImage: state.mute ? "speaker.slash.fill" : "speaker.fill") {
                send(.set(.mute, !state.mute))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 24)
            Bar(value: state.volume, range: 0...max(state.volumeMax, 1), dragging: $dragging)
                .opacity(state.mute ? 0.4 : 1)
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .onChange(of: dragging) { _, volume in
            if let volume { send(.set(.volume, volume.rounded())) }
        }
    }
}

private struct PanelSheet: View {
    let panel: Panel
    let player: Player

    var body: some View {
        NavigationStack {
            if let state = player.state {
                switch panel {
                case .subtitles: TracksForm(kind: .sub, state: state, send: player.send)
                case .audio: TracksForm(kind: .audio, state: state, send: player.send)
                case .library: LibraryList(state: state, library: player.library, send: player.send)
                }
            }
        }
    }
}

private struct TracksForm: View {
    let kind: PlayerState.Track.Kind
    let state: PlayerState
    let send: (Command) -> Void

    var body: some View {
        let tracks = state.tracks.filter { $0.type == kind }
        Form {
            if kind == .sub {
                Toggle("Show Subtitles", isOn: Binding(get: { state.subVisible }, set: { send(.set(.subVisibility, $0)) }))
            }
            Section("Track") {
                if kind == .audio, tracks.isEmpty {
                    Text("No audio tracks").foregroundStyle(.secondary)
                } else {
                    Picker("Track", selection: Binding(get: { kind == .sub ? state.sid : state.aid },
                                                       set: { send(.set(kind == .sub ? .sid : .aid, $0)) })) {
                        if kind == .sub { Text("Off").tag("no") }
                        ForEach(tracks) { Text($0.label).tag(String($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            Section("Delay") {
                DelayRow(value: kind == .sub ? state.subDelay : state.audioDelay, property: kind == .sub ? .subDelay : .audioDelay, send: send)
            }
        }
        .navigationTitle(kind == .sub ? "Subtitles" : "Audio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DelayRow: View {
    let value: Double
    let property: Command.Property
    let send: (Command) -> Void

    var body: some View {
        HStack {
            button("Back 1 Second", "chevron.left.2", -1)
            Spacer()
            button("Back 0.1 Seconds", "chevron.left", -0.1)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(1)))) s")
                .monospacedDigit()
                .frame(minWidth: 64)
            Spacer()
            button("Forward 0.1 Seconds", "chevron.right", 0.1)
            Spacer()
            button("Forward 1 Second", "chevron.right.2", 1)
        }
        .padding(.horizontal, 8)
    }

    private func button(_ title: String, _ symbol: String, _ step: Double) -> some View {
        Button(title, systemImage: symbol) { send(.set(property, ((value + step) * 10).rounded() / 10)) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
    }
}

private struct LibraryList: View {
    enum Tab: String, CaseIterable {
        case playlist = "Playlist"
        case chapters = "Chapters"
        case recent = "Recent"
    }

    let state: PlayerState
    let library: Library?
    let send: (Command) -> Void

    @State private var tab: Tab?
    @Environment(\.dismiss) private var dismiss

    private var tabs: [Tab] {
        guard let library else { return [] }
        return [library.playlist.count > 1 ? .playlist : nil, library.chapters.isEmpty ? nil : .chapters, library.recent.isEmpty ? nil : .recent]
            .compactMap(\.self)
    }

    var body: some View {
        let tab = tab ?? tabs.first
        List {
            if let library {
                switch tab {
                case .playlist:
                    ForEach(Array(library.playlist.enumerated()), id: \.offset) { index, item in
                        row(item.title, number: index + 1, isCurrent: item.current) { send(.playItem(index)) }
                    }
                case .chapters:
                    ForEach(Array(library.chapters.enumerated()), id: \.offset) { index, chapter in
                        row(chapter.title.isEmpty ? "Chapter \(index + 1)" : chapter.title, number: index + 1,
                            time: clock(chapter.start, of: state.duration), isCurrent: state.chapter == index) {
                            send(.playChapter(index))
                        }
                    }
                case .recent:
                    ForEach(library.recent) { recent in
                        RecentRow(recent: recent) {
                            send(.openRecent(recent.url))
                            dismiss()
                        }
                    }
                case nil:
                    Text("Nothing up next").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(tab?.rawValue ?? "Up Next")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if tabs.count > 1 {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: Binding(get: { tab ?? .recent }, set: { self.tab = $0 })) {
                        ForEach(tabs, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }

    private func row(_ title: String, number: Int, time: String? = nil, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if isCurrent {
                        Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: !state.pause)
                    } else {
                        Text("\(number)")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
                Text(title).lineLimit(1).fontWeight(isCurrent ? .semibold : .regular)
                Spacer()
                if let time { Text(time).foregroundStyle(.secondary) }
            }
            .monospacedDigit()
        }
        .tint(.primary)
    }
}

private struct RecentRow: View {
    let recent: Library.Recent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(recent.title).lineLimit(1)
                if recent.fraction > 0 {
                    ProgressView(value: recent.fraction).tint(.accentColor)
                }
            }
        }
        .tint(.primary)
    }
}

private struct Idle: View {
    let recent: [Library.Recent]
    let send: (Command) -> Void

    var body: some View {
        if recent.isEmpty {
            ContentUnavailableView("Nothing Playing", systemImage: "play.tv", description: Text("Open a video in IINA on your Mac."))
        } else {
            List {
                Section("Continue Watching") {
                    ForEach(recent) { recent in RecentRow(recent: recent) { send(.openRecent(recent.url)) } }
                }
            }
        }
    }
}

private func clock(_ seconds: Double, of duration: Double) -> String {
    Duration.seconds(max(0, seconds).rounded(.down)).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
}
