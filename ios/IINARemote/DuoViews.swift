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
                ArrangementView {
                    NowPlayingScreen(player: player, state: state, showsBackdrop: false)
                } secondary: {
                    LibraryList(state: state, library: player.library, send: player.send, inline: true)
                }
                .arrangementViewStyle(.split)
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
