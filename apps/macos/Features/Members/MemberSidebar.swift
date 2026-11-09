import SwiftUI

struct MemberSidebar: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Membres").font(.headline)
                Spacer()
                Text(model.members.count, format: .number)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            Form {
                if model.isConnected { memberGroup("Membres", online: false) }
                else {
                    memberGroup("En ligne", online: true)
                    memberGroup("Hors ligne", online: false)
                }
            }
            .formStyle(.grouped)
        }
        .accessibilityLabel("Inspecteur des membres")
        .accessibilityIdentifier("members.sidebar")
    }

    private func memberGroup(_ title: String, online: Bool) -> some View {
        let members = model.members.filter { $0.online == online }
        return Section("\(title) — \(members.count)") {
            ForEach(members, id: \.user.id) { member in
                Button { model.profile = member.user } label: {
                    HStack(spacing: 10) {
                        AvatarView(user: member.user, size: 32)
                            .overlay(alignment: .bottomTrailing) {
                                if !model.isConnected { Circle().fill(online ? Color.green : Color.secondary)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(.background, lineWidth: 2)) }
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.user.displayName).font(.callout.weight(.medium))
                            Text(member.role).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(member.user.displayName), \(member.role), \(model.isConnected ? "membre" : online ? "en ligne" : "hors ligne")")
                .accessibilityIdentifier("member.\(member.user.id)")
            }
        }
    }
}

struct ProfileView: View {
    let user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            AvatarView(user: user, size: 76)
            Text(user.displayName).font(.title2.bold())
                .accessibilityIdentifier("profile.name")
            Text(user.bio).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Divider()
            Label(model.isConnected ? "Profil du serveur" : "Profil de démonstration", systemImage: "person.crop.circle")
                .font(.caption).foregroundStyle(.secondary)
            Button("Fermer") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("profile.close")
        }
        .padding(32)
        .frame(width: 320)
    }
}
