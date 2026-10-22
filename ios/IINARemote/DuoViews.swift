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

/// Everything the player's bottom bar opens as sheets, always on screen next to it.
private struct SidePanel: View {
    enum Tab: String {
        case playlist = "Playlist"
        case chapters = "Chapters"
        case subtitles = "Subtitles"
        case audio = "Audio"
        case recent = "Recent"
    }

    let player: Player
    let state: PlayerState

    @State private var tab: Tab?

    private var tabs: [Tab] {
        let library = player.library
        return [
            (library?.playlist.count ?? 0) > 1 ? .playlist : nil,
            library?.chapters.isEmpty == false ? .chapters : nil,
            .subtitles,
            .audio,
            library?.recent.isEmpty == false ? .recent : nil,
        ].compactMap(\.self)
    }

    var body: some View {
        let tab = tab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs[0]
        Group {
            switch tab {
            case .playlist: LibraryList(state: state, library: player.library, send: player.send, inline: true, only: .playlist)
            case .chapters: LibraryList(state: state, library: player.library, send: player.send, inline: true, only: .chapters)
            case .recent: LibraryList(state: state, library: player.library, send: player.send, inline: true, only: .recent)
            case .subtitles: TracksForm(kind: .sub, state: state, send: player.send, inline: true)
            case .audio: TracksForm(kind: .audio, state: state, send: player.send, inline: true)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Show", selection: Binding(get: { tab }, set: { self.tab = $0 })) {
                ForEach(tabs, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
