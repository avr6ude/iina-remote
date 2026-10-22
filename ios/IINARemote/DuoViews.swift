import SwiftUI

/// Lays the player out around iPhone Duo's fold; on other iPhones it's the usual player.
@available(iOS 27.1, *)
struct DuoPlayer: View {
    let player: Player
    let state: PlayerState

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.reservedRegions(kind: .division).first(where: \.isActive)
            if let fold, fold.frame.width > fold.frame.height {
                Tabletop(player: player, state: state, fold: fold.frame)
            } else if proxy.size.width > 600 {
                // The fold is reported even when the phone lies flat, so each half keeps clear of the hinge.
                let hinge = proxy.reservedRegions(kind: .division, options: [.includeInactive]).first
                HStack(spacing: 0) {
                    NowPlayingScreen(player: player, state: state, showsBackdrop: false, showsPanelBar: false)
                        .frame(width: hinge.map { $0.frame.minX - 12 } ?? proxy.size.width / 2)
                    Color.clear
                        .frame(width: hinge.map { $0.frame.width + 24 } ?? 0)
                    SidePanel(player: player, state: state)
                }
                .background { Backdrop(artwork: player.artwork) }
            } else {
                NowPlayingScreen(player: player, state: state)
            }
        }
    }
}

/// Half folded and standing up: the top half is a small TV, the bottom half the remote.
@available(iOS 27.1, *)
private struct Tabletop: View {
    let player: Player
    let state: PlayerState
    let fold: CGRect

    @State private var panel: Panel?

    var body: some View {
        VStack(spacing: 0) {
            screen.frame(height: fold.minY)
            Color.clear.frame(height: fold.height)
            remote
        }
        .background { Backdrop(artwork: player.artwork) }
        .preferredColorScheme(.dark)
        .sheet(item: $panel) { panel in
            PanelSheet(panel: panel, player: player).presentationDetents([.medium, .large])
        }
    }

    private var screen: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if let artwork = player.artwork {
                Image(uiImage: artwork.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            }
            VStack(spacing: 2) {
                Text(state.title).font(.title3.weight(.semibold)).lineLimit(1)
                if let subtitle = player.subtitle(for: state) { Text(subtitle).foregroundStyle(.secondary).lineLimit(1) }
            }
            Scrubber(state: state, send: player.send)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
    }

    private var remote: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Transport(player: player, state: state, scale: 1.25)
            Spacer(minLength: 0)
            Volume(state: state, send: player.send)
            Spacer(minLength: 0)
            PanelBar(state: state, send: player.send, panel: $panel)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }
}

/// What the player's bottom bar opens as sheets, kept on screen next to it as one list.
private struct SidePanel: View {
    let player: Player
    let state: PlayerState

    @State private var tab: LibraryList.Tab?

    var body: some View {
        let tabs = LibraryList.Tab.available(in: player.library)
        let tab = tab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first
        List {
            Section("Subtitles") {
                Picker("Track", selection: Binding(get: { state.subVisible ? state.sid : "no" }, set: selectSubtitles)) {
                    Text("Off").tag("no")
                    ForEach(state.tracks.filter { $0.type == .sub }) { Text($0.label).tag(String($0.id)) }
                }
                DelayRow(value: state.subDelay, property: .subDelay, send: player.send)
            }
            .panelRows()
            Section("Audio") {
                Picker("Track", selection: Binding(get: { state.aid }, set: { player.send(.set(.aid, $0)) })) {
                    ForEach(state.tracks.filter { $0.type == .audio }) { Text($0.label).tag(String($0.id)) }
                }
                DelayRow(value: state.audioDelay, property: .audioDelay, send: player.send)
                Picker("Speed", selection: Binding(get: { state.speed }, set: { player.send(.set(.speed, $0)) })) {
                    ForEach(PanelBar.speeds, id: \.self) { Text("\($0.formatted())×").tag($0) }
                }
            }
            .panelRows()
            if !tabs.isEmpty {
                Section {
                    LibraryRows(tab: tab, state: state, library: player.library, send: player.send)
                } header: {
                    if tabs.count > 1 {
                        Picker("Up Next", selection: Binding(get: { tab ?? tabs[0] }, set: { self.tab = $0 })) {
                            ForEach(tabs, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 6)
                    } else {
                        Text(tab?.rawValue ?? "Up Next")
                    }
                }
                .panelRows()
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectHidden(true, for: .top)
    }

    private func selectSubtitles(_ id: String) {
        if id != "no" { player.send(.set(.sid, id)) }
        player.send(.set(.subVisibility, id != "no"))
    }
}

private extension View {
    /// See-through rows over the artwork backdrop; it only reaches rows, so it goes on each section.
    func panelRows() -> some View {
        listRowBackground(Color.white.opacity(0.1))
    }
}
