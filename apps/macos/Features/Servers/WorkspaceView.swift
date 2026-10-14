import SwiftUI

struct WorkspaceView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NativeWorkspace(model: model, showSidebar: $model.showSidebar, showMembers: $model.showMembers, openSettings: { openSettings() })
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: Binding(
            get: { model.profile != nil },
            set: { if !$0 { model.profile = nil } }
        )) {
            if let user = model.profile { ProfileView(user: user) }
        }
    }
}

struct ServerSidebar: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        List(selection: Binding(
            get: { model.selectedServerID },
            set: { if let id = $0 { model.selectServer(id) } }
        )) {
            ForEach(model.servers, id: \.id) { server in
                let selected = model.selectedServerID == server.id
                Text(server.initials)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: 48, height: 48)
                    .background(
                        selected ? Color.accentColor : Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: selected ? 14 : 24)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .tag(server.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .help(server.name)
                    .accessibilityLabel(server.name)
                    .accessibilityIdentifier("server.\(server.id)")
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.horizontal, 8, for: .scrollContent)
        .accessibilityLabel("Serveurs")
        .accessibilityIdentifier("navigation.servers")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let user = model.currentUser {
                Button { model.profile = user } label: {
                    AvatarView(user: user, size: 36)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Votre profil, \(user.displayName)")
                    .accessibilityIdentifier("workspace.profile")
                    .help("Votre profil")
            }
        }
    }
}
