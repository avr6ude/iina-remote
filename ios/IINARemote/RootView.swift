import SwiftUI

struct RootView: View {
    @State private var discovery = Discovery()
    @AppStorage("selectedPlayer") private var selectedName = ""
    @State private var wasInBackground = false
    @Environment(\.scenePhase) private var scenePhase

    private var selected: Player? { discovery.players.first { $0.name == selectedName } }

    var body: some View {
        NavigationStack {
            if let selected, discovery.players.count > 1 {
                RemoteView(player: selected).toolbarTitleMenu { playerMenu }
            } else if let selected {
                RemoteView(player: selected)
            } else if discovery.players.isEmpty {
                searching
            } else {
                PlayerList(players: discovery.players, selectedName: $selectedName)
            }
        }
        .onChange(of: discovery.players.map(\.name), initial: true) { _, names in
            if !names.contains(selectedName), names.count == 1 { selectedName = names[0] }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { wasInBackground = true }
            if phase == .active, wasInBackground {
                wasInBackground = false
                discovery.refresh()
            }
        }
    }

    private var playerMenu: some View {
        ForEach(discovery.players) { player in
            Toggle(isOn: Binding(get: { player.name == selectedName }, set: { _ in selectedName = player.name })) {
                Text(player.name)
                Text(player.subtitle)
            }
        }
    }

    @ViewBuilder private var searching: some View {
        if discovery.isDenied {
            ContentUnavailableView {
                Label("Local Network Access Off", systemImage: "wifi.exclamationmark")
            } description: {
                Text("IINA Remote needs Local Network access to find your Mac.")
            } actions: {
                Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            }
        } else {
            ContentUnavailableView {
                Label("Looking for IINA…", systemImage: "play.tv")
            } description: {
                Text("Open a video in IINA on a Mac on this network, with the Remote plugin enabled.")
            }
        }
    }
}

private struct PlayerList: View {
    let players: [Player]
    @Binding var selectedName: String

    var body: some View {
        List(players.sorted { ($0.isPlaying ? 0 : 1) < ($1.isPlaying ? 0 : 1) }) { player in
            Button {
                selectedName = player.name
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(player.name)
                        Text(player.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if player.name == selectedName { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .tint(.primary)
        }
        .navigationTitle("Choose IINA")
    }
}

private extension Player {
    var isPlaying: Bool { !(state?.title.isEmpty ?? true) }
    var subtitle: String {
        guard let state else { return "Connecting…" }
        return state.title.isEmpty ? "Nothing playing" : state.title
    }
}
