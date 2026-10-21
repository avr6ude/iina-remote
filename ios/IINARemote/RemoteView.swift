import SwiftUI

struct RemoteView: View {
    let player: Player

    var body: some View {
        Group {
            if let state = player.state {
                Controls(state: state, library: player.library, send: player.send)
            } else {
                ProgressView("Connecting…")
            }
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Controls: View {
    let state: PlayerState
    let library: Library?
    let send: (Command) -> Void

    @State private var scrubTime: Double?

    private static let speeds = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        Form {
            Section {
                Text(state.title.isEmpty ? "Nothing playing" : state.title)
                    .font(.headline)
                    .lineLimit(2)
                position
                transport
            }

            Section("Volume") {
                HStack(spacing: 12) {
                    Button(state.mute ? "Unmute" : "Mute", systemImage: state.mute ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                        send(.set(.mute, !state.mute))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 28)
                    Slider(value: binding(state.volume, .volume), in: 0...max(state.volumeMax, 1))
                }
            }

            Section {
                Picker("Speed", selection: binding(state.speed, .speed)) {
                    ForEach(Self.speeds, id: \.self) { Text("\($0.formatted())×").tag($0) }
                }
            }

            Section("Subtitles") {
                Picker("Track", selection: binding(state.sid, .sid)) {
                    Text("Off").tag("no")
                    tracks(.sub)
                }
                Toggle("Show Subtitles", isOn: binding(state.subVisible, .subVisibility))
                delayRow(state.subDelay, .subDelay)
            }

            Section("Audio") {
                Picker("Track", selection: binding(state.aid, .aid)) { tracks(.audio) }
                delayRow(state.audioDelay, .audioDelay)
            }

            if let library {
                librarySections(library)
            }
        }
    }

    @ViewBuilder private func librarySections(_ library: Library) -> some View {
        if library.playlist.count > 1 {
            Section("Playlist") {
                ForEach(Array(library.playlist.enumerated()), id: \.offset) { index, item in
                    row(item.title, isCurrent: item.current) { send(.playItem(index)) }
                }
            }
        }
        if !library.chapters.isEmpty {
            Section("Chapters") {
                ForEach(Array(library.chapters.enumerated()), id: \.offset) { index, chapter in
                    row(chapter.title.isEmpty ? "Chapter \(index + 1)" : chapter.title, detail: clock(chapter.start), isCurrent: state.chapter == index) {
                        send(.playChapter(index))
                    }
                }
            }
        }
        if !library.recent.isEmpty {
            Section("Recent") {
                ForEach(library.recent) { recent in
                    Button { send(.openRecent(recent.url)) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recent.title).lineLimit(1)
                            if recent.fraction > 0 { ProgressView(value: recent.fraction) }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    private func row(_ title: String, detail: String? = nil, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(1).fontWeight(isCurrent ? .semibold : .regular)
                Spacer()
                if let detail { Text(detail).monospacedDigit().foregroundStyle(.secondary) }
                if isCurrent { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }
            }
        }
        .tint(.primary)
    }

    private var position: some View {
        let duration = max(state.duration, 1)
        let time = min(scrubTime ?? state.time, duration)
        return VStack(spacing: 2) {
            Slider(value: Binding(get: { time }, set: { scrubTime = $0 }), in: 0...duration) { editing in
                guard !editing, let scrubTime else { return }
                send(.seek(scrubTime, absolute: true))
                self.scrubTime = nil
            }
            HStack {
                Text(clock(time))
                Spacer()
                Text("-" + clock(duration - time))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack {
            Button("Previous", systemImage: "backward.end.fill") { send(.previous) }
            Spacer()
            Button("Back 10 Seconds", systemImage: "gobackward.10") { send(.seek(-10, absolute: false)) }
            Spacer()
            Button(state.pause ? "Play" : "Pause", systemImage: state.pause ? "play.fill" : "pause.fill") { send(.set(.pause, !state.pause)) }
                .font(.largeTitle)
                .contentTransition(.symbolEffect(.replace))
            Spacer()
            Button("Forward 30 Seconds", systemImage: "goforward.30") { send(.seek(30, absolute: false)) }
            Spacer()
            Button("Next", systemImage: "forward.end.fill") { send(.next) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title2)
        .tint(.primary)
        .padding(.vertical, 6)
    }

    private func tracks(_ kind: PlayerState.Track.Kind) -> some View {
        ForEach(state.tracks.filter { $0.type == kind }) { Text($0.label).tag(String($0.id)) }
    }

    private func delayRow(_ value: Double, _ property: Command.Property) -> some View {
        HStack(spacing: 18) {
            Text("Delay")
            Spacer()
            delayButton("Back 1 Second", "chevron.left.2", value - 1, property)
            delayButton("Back 0.1 Seconds", "chevron.left", value - 0.1, property)
            Text("\(value.formatted(.number.precision(.fractionLength(1)))) s")
                .monospacedDigit()
                .frame(minWidth: 52)
            delayButton("Forward 0.1 Seconds", "chevron.right", value + 0.1, property)
            delayButton("Forward 1 Second", "chevron.right.2", value + 1, property)
        }
    }

    private func delayButton(_ title: String, _ symbol: String, _ target: Double, _ property: Command.Property) -> some View {
        Button(title, systemImage: symbol) { send(.set(property, (target * 10).rounded() / 10)) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
    }

    private func clock(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: state.duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    private func binding(_ value: Bool, _ property: Command.Property) -> Binding<Bool> {
        Binding(get: { value }, set: { send(.set(property, $0)) })
    }

    private func binding(_ value: Double, _ property: Command.Property) -> Binding<Double> {
        Binding(get: { value }, set: { send(.set(property, $0)) })
    }

    private func binding(_ value: String, _ property: Command.Property) -> Binding<String> {
        Binding(get: { value }, set: { send(.set(property, $0)) })
    }
}
