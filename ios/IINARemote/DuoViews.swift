import SwiftUI

/// Lays the player out around iPhone Duo's fold; on other iPhones it's the usual player.
@available(iOS 27.1, *)
struct DuoPlayer: View {
    let player: Player
    let state: PlayerState

    @State private var hinge: DeviceHinge?

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.reservedRegions(kind: .division).first(where: \.isActive)
            if let fold, fold.frame.width > fold.frame.height {
                Tabletop(player: player, state: state, fold: fold.frame, hinge: hinge)
            } else if proxy.size.width > 600 {
                ArrangementView {
                    NowPlayingScreen(player: player, state: state)
                } secondary: {
                    PanelSheet(panel: .library, player: player)
                }
                .arrangementViewStyle(.split)
            } else {
                NowPlayingScreen(player: player, state: state)
            }
        }
        .onHingeChange { _, context in hinge = context.hinge }
    }
}

/// Half folded and standing on a table: the top half is a small TV, the bottom half a touchpad.
@available(iOS 27.1, *)
private struct Tabletop: View {
    let player: Player
    let state: PlayerState
    let fold: CGRect
    let hinge: DeviceHinge?

    var body: some View {
        VStack(spacing: 0) {
            screen
                .frame(height: fold.minY)
            Color.clear.frame(height: fold.height)
            Touchpad(state: state, send: player.send)
        }
        .background { Backdrop(artwork: player.artwork) }
        .preferredColorScheme(.dark)
        .ignoresSafeArea(edges: .bottom)
    }

    /// How far the top half leans back from upright, so the artwork can lean with it.
    private var lean: Double {
        guard let hinge else { return 0 }
        return max(0, min(60, hinge.angle.degrees - 90))
    }

    private var screen: some View {
        HStack(spacing: 24) {
            if let artwork = player.artwork {
                Image(uiImage: artwork.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    .rotation3DEffect(.degrees(-lean / 3), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .animation(.smooth, value: lean)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title).font(.title2.weight(.semibold)).lineLimit(2)
                Text(player.name).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Scrubber(state: state, send: player.send)
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }
}

/// An Apple TV-style surface: tap to play or pause, swipe sideways to skip, drag up or down for volume.
private struct Touchpad: View {
    let state: PlayerState
    let send: (Command) -> Void

    @State private var feedback: String?
    @State private var startVolume: Double?

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.white.opacity(0.07))
            .overlay {
                Image(systemName: feedback ?? (state.pause ? "play.fill" : "pause.fill"))
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(feedback == nil ? 0.25 : 0.9))
                    .contentTransition(.symbolEffect(.replace))
            }
            .overlay(alignment: .bottom) {
                Text("Tap to play or pause · Swipe to skip · Drag up or down for volume")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
            .contentShape(.rect)
            .gesture(drag)
            .onTapGesture {
                send(.set(.pause, !state.pause))
                flash(state.pause ? "play.fill" : "pause.fill")
            }
            .sensoryFeedback(.impact(weight: .light), trigger: feedback)
            .padding(24)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { drag in
                guard abs(drag.translation.height) > abs(drag.translation.width) else { return }
                let start = startVolume ?? state.volume
                startVolume = start
                let volume = min(max(start - drag.translation.height / 3, 0), state.volumeMax)
                send(.set(.volume, volume.rounded()))
                feedback = volume > start ? "speaker.wave.3.fill" : "speaker.wave.1.fill"
            }
            .onEnded { drag in
                defer { startVolume = nil; flash(nil) }
                guard abs(drag.translation.width) > abs(drag.translation.height), abs(drag.translation.width) > 60 else { return }
                let forward = drag.translation.width > 0
                send(.seek(forward ? 30 : -10, absolute: false))
                flash(forward ? "goforward.30" : "gobackward.10")
            }
    }

    private func flash(_ symbol: String?) {
        feedback = symbol
        guard symbol != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            if feedback == symbol { feedback = nil }
        }
    }
}
