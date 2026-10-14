import SwiftUI

struct ChannelSidebar: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        List(selection: Binding(
            get: { model.selectedChannelID },
            set: { if let id = $0 { model.selectChannel(id) } }
        )) {
            Section(model.selectedServer?.name ?? "Salons") {
                ForEach(model.channels, id: \.id) { channel in
                    Label(channel.name, systemImage: "number")
                        .tag(channel.id)
                        .accessibilityIdentifier("channel.\(channel.id)")
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Salons du serveur")
        .accessibilityIdentifier("navigation.channels")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Label("Conversations locales", systemImage: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(16)
        }
    }
}
