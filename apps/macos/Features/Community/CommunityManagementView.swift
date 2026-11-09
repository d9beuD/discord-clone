import SwiftUI

struct JoinServerView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Créer ou rejoindre un serveur").font(.title2.bold())
            Form {
                Section("Nouveau serveur") {
                    TextField("Nom du serveur", text: $name)
                    Button("Créer le serveur") {
                        Task { if await model.createGuild(name: name) { dismiss() } }
                    }.disabled(name.isEmpty)
                    .accessibilityIdentifier("guild.create")
                }
                Section("Invitation") {
                    TextField("Code d’invitation", text: $token)
                    Button("Rejoindre le serveur") {
                        Task { if await model.acceptInvite(token: token) { token = ""; dismiss() } }
                    }.disabled(token.isEmpty)
                    .accessibilityIdentifier("guild.join")
                }
            }.formStyle(.grouped).disabled(model.isWorking)
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if model.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Fermer") { token = ""; dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 480, height: 430)
    }
}

struct CommunityManagementView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Serveur"
    @State private var guildName = ""
    @State private var channelName = ""
    @State private var channelKind: ChannelKind = .text
    @State private var roleName = ""
    @State private var rolePermissions: Int64 = 3
    @State private var expiresInSeconds: Int64 = 86400
    @State private var maxUses: Int64 = 10
    @State private var unlimitedUses = false
    @State private var confirmationTitle = ""
    @State private var confirmation: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.selectedServer?.name ?? "Gestion du serveur").font(.title2.bold())
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("Gestion", selection: $tab) {
                ForEach(["Serveur", "Salons", "Membres", "Rôles", "Invitations", "Permissions"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if let workspace = model.workspace {
                Form {
                    switch tab {
                    case "Serveur": serverSection(workspace)
                    case "Salons": channelSection(workspace)
                    case "Membres": memberSection(workspace)
                    case "Rôles": roleSection(workspace)
                    case "Invitations": inviteSection(workspace)
                    default: overrideSection(workspace)
                    }
                }
                .formStyle(.grouped)
                .disabled(model.isWorking)
            } else {
                ContentUnavailableView("Chargement du serveur", systemImage: "network")
            }
        }
        .padding(24)
        .frame(width: 680, height: 660)
        .onAppear { guildName = model.selectedServer?.name ?? "" }
        .onDisappear { model.createdInviteToken = nil }
        .task(id: tab) { await loadTab() }
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible) {
            Button("Confirmer", role: .destructive) { let action = confirmation; confirmation = nil; action?() }
            Button("Annuler", role: .cancel) { confirmation = nil }
        }
    }

    private func loadTab() async {
        if tab == "Invitations", model.workspace?.canManageChannels == true { await model.loadInvites() }
        if tab == "Permissions" { await model.loadOverrides() }
    }
    private func confirm(_ title: String, action: @escaping () -> Void) {
        confirmationTitle = title
        confirmation = action
    }

    @ViewBuilder private func serverSection(_ workspace: BackendWorkspace) -> some View {
        Section("Serveur") {
            LabeledContent("Identifiant", value: workspace.guild.id).textSelection(.enabled)
            if workspace.isOwner {
                TextField("Nom", text: $guildName)
                Button("Renommer") {
                    let name = guildName
                    Task { _ = await model.performBackend { _ = try $0.renameGuild(guildId: workspace.guild.id, name: name) } }
                }
                Button("Supprimer le serveur…", role: .destructive) {
                    confirm("Supprimer ce serveur, ses salons, rôles et invitations ? Cette action est définitive.") {
                        // Deleting a server changes the server list, so refresh it explicitly.
                        Task { if await model.performAction({ try $0.deleteGuild(guildId: workspace.guild.id) }) { _ in await model.refreshBackend() } { dismiss() } }
                    }
                }
            } else {
                Button("Quitter le serveur…", role: .destructive) {
                    confirm("Quitter ce serveur ? Une invitation sera nécessaire pour le rejoindre à nouveau.") {
                        Task { if await model.performBackend({ try $0.leaveGuild(guildId: workspace.guild.id) }) { dismiss() } }
                    }
                }
            }
        }
    }

    @ViewBuilder private func channelSection(_ workspace: BackendWorkspace) -> some View {
        if workspace.canManageChannels {
            Section("Créer un salon") {
                TextField("Nom", text: $channelName)
                Picker("Type", selection: $channelKind) { Text("Texte").tag(ChannelKind.text); Text("Vocal").tag(ChannelKind.voice) }
                Button("Créer") {
                    let name = channelName
                    let kind = channelKind
                    Task {
                        if await model.performBackend({ _ = try $0.createChannel(guildId: workspace.guild.id, name: name, kind: kind, position: 0) }) { channelName = "" }
                    }
                }.disabled(channelName.isEmpty)
            }
        }
        Section("Salons visibles") {
            ForEach(workspace.remoteChannels, id: \.id) { channel in
                DisclosureGroup(channel.name) {
                    ChannelManagementRow(channel: channel, confirm: confirm).id(channel)
                }
            }
            if workspace.remoteChannels.isEmpty { Text("Aucun salon visible.").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func memberSection(_ workspace: BackendWorkspace) -> some View {
        Section("Membres") {
            ForEach(workspace.guildMembers, id: \.userId) { member in
                DisclosureGroup(member.username) {
                    Text(member.userId).font(.caption).textSelection(.enabled)
                    if workspace.canManageRoles {
                        ForEach(workspace.roles.filter { !$0.isDefault }, id: \.id) { role in
                            let assigned = member.roleIds.contains(role.id)
                            Button("\(assigned ? "Retirer" : "Attribuer") : \(role.name)") {
                                Task { _ = await model.performBackend { try $0.setMemberRole(guildId: workspace.guild.id, userId: member.userId, roleId: role.id, assigned: !assigned) } }
                            }
                        }
                    }
                    if workspace.canKickMembers, member.userId != workspace.guild.ownerId, member.userId != model.currentUser?.id {
                        Button("Expulser…", role: .destructive) {
                            confirm("Expulser \(member.username) du serveur ?") {
                                Task { _ = await model.performBackend { try $0.kickMember(guildId: workspace.guild.id, userId: member.userId) } }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func roleSection(_ workspace: BackendWorkspace) -> some View {
        if workspace.canManageRoles {
            Section("Créer un rôle") {
                TextField("Nom", text: $roleName)
                PermissionEditor(title: "Permissions", value: $rolePermissions)
                Button("Créer") {
                    let name = roleName
                    let permissions = rolePermissions
                    Task { if await model.performBackend({ _ = try $0.createRole(guildId: workspace.guild.id, name: name, permissions: permissions) }) { roleName = "" } }
                }.disabled(roleName.isEmpty)
            }
        }
        Section("Rôles du serveur") {
            ForEach(workspace.roles, id: \.id) { role in
                DisclosureGroup(role.name) {
                    RoleManagementRow(role: role, canEdit: workspace.canManageRoles, confirm: confirm).id(role)
                }
            }
        }
    }

    @ViewBuilder private func inviteSection(_ workspace: BackendWorkspace) -> some View {
        if workspace.canManageChannels {
            Section("Créer une invitation") {
                TextField("Durée en secondes (1 à 604 800)", value: $expiresInSeconds, format: .number)
                Toggle("Utilisations illimitées", isOn: $unlimitedUses)
                if !unlimitedUses { TextField("Utilisations maximales", value: $maxUses, format: .number) }
                Button("Créer le code") {
                    Task { await model.createInvite(expiresInSeconds: expiresInSeconds, maxUses: unlimitedUses ? nil : maxUses) }
                }
                if let token = model.createdInviteToken {
                    Text("Copiez ce code : il ne pourra plus être relu après fermeture.").font(.caption)
                    Text(token).textSelection(.enabled).font(.system(.body, design: .monospaced))
                    ShareLink("Partager le code", item: token)
                }
            }
            Section("Invitations") {
                ForEach(model.invites, id: \.id) { invite in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(invite.id).font(.caption).textSelection(.enabled)
                        Text("\(invite.uses) utilisation(s) · expiration : \(invite.expiresAt ?? "aucune")").font(.caption)
                        if invite.revokedAt == nil {
                            Button("Révoquer…", role: .destructive) {
                                confirm("Révoquer cette invitation ? Son code cessera de fonctionner.") {
                                    Task { _ = await model.performAction({ try $0.revokeInvite(guildId: workspace.guild.id, inviteId: invite.id) }) { _ in await model.loadInvites() } }
                                }
                            }
                        } else { Text("Révoquée").foregroundStyle(.secondary) }
                    }
                }
            }
        } else { Section { Text("La gestion des invitations nécessite la permission de gérer les salons.") } }
    }

    @ViewBuilder private func overrideSection(_ workspace: BackendWorkspace) -> some View {
        Section("Salon sélectionné") {
            Text(model.selectedChannel?.name ?? "Aucun salon")
            if let access = model.channelAccess {
                PermissionEditor(title: "Vos droits effectifs", value: .constant(access.permissions), readOnly: true)
                if access.canManageRoles, let channelID = model.selectedChannelID {
                    OverrideManagementForm(channelID: channelID, workspace: workspace)
                    ForEach(model.overrides, id: \.id) { override in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(targetName(override, workspace: workspace))
                            PermissionEditor(title: "Autorisations", value: .constant(override.allowPermissions), readOnly: true)
                            PermissionEditor(title: "Refus", value: .constant(override.denyPermissions), readOnly: true)
                            Button("Retirer l’exception…", role: .destructive) {
                                confirm("Retirer cette exception de permissions ?") {
                                    Task {
                                        _ = await model.performBackend { try $0.deleteOverride(channelId: channelID, overrideId: override.id) }
                                        await model.loadOverrides()
                                    }
                                }
                            }
                        }
                    }
                }
            } else { Text("Sélectionnez un salon pour charger ses permissions.").foregroundStyle(.secondary) }
        }
    }
    private func targetName(_ override: ChannelOverride, workspace: BackendWorkspace) -> String {
        if let id = override.roleId { return workspace.roles.first { $0.id == id }?.name ?? id }
        return workspace.guildMembers.first { $0.userId == override.memberId }?.username ?? override.memberId ?? "Cible inconnue"
    }
}

private struct ChannelManagementRow: View {
    let channel: RemoteChannel
    let confirm: (String, @escaping () -> Void) -> Void
    @Environment(AppViewModel.self) private var model
    @State private var name = ""
    @State private var position: Int32 = 0
    @State private var access: ChannelAccess?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(channel.kind == .voice ? "Salon vocal" : "Salon texte").foregroundStyle(.secondary)
            if access?.canManageChannels == true {
                TextField("Nom", text: $name)
                Stepper("Position : \(position)", value: $position, in: 0...Int32.max)
                Button("Enregistrer") {
                    let updatedName = name
                    let updatedPosition = position
                    Task { _ = await model.performBackend { _ = try $0.updateChannel(channelId: channel.id, name: updatedName, position: updatedPosition) } }
                }
                Button("Supprimer le salon…", role: .destructive) {
                    confirm("Supprimer le salon \(channel.name) ? Cette action est définitive.") {
                        Task { _ = await model.performBackend { try $0.deleteChannel(channelId: channel.id) } }
                    }
                }
            }
        }
        .onAppear { name = channel.name; position = channel.position }
        .task(id: model.workspace) {
            let result = await model.accessForChannel(channel.id)
            access = result
        }
    }
}

private struct RoleManagementRow: View {
    let role: Role
    let canEdit: Bool
    let confirm: (String, @escaping () -> Void) -> Void
    @Environment(AppViewModel.self) private var model
    @State private var name = ""
    @State private var permissions: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !role.isDefault { TextField("Nom", text: $name).disabled(!canEdit) }
            PermissionEditor(title: "Permissions", value: $permissions, readOnly: !canEdit)
            if canEdit {
                Button("Enregistrer") {
                    let updatedName = role.isDefault ? nil : name
                    let updatedPermissions = permissions
                    Task { _ = await model.performBackend { _ = try $0.updateRole(guildId: role.guildId, roleId: role.id, name: updatedName, permissions: updatedPermissions) } }
                }
                if !role.isDefault {
                    Button("Supprimer le rôle…", role: .destructive) {
                        confirm("Supprimer le rôle \(role.name) et ses attributions ?") {
                            Task { _ = await model.performBackend { try $0.deleteRole(guildId: role.guildId, roleId: role.id) } }
                        }
                    }
                }
            }
        }.onAppear { name = role.name; permissions = role.permissions }
    }
}

private struct OverrideManagementForm: View {
    let channelID: String
    let workspace: BackendWorkspace
    @Environment(AppViewModel.self) private var model
    @State private var memberTarget = false
    @State private var target = ""
    @State private var allow: Int64 = 0
    @State private var deny: Int64 = 0

    var body: some View {
        DisclosureGroup("Ajouter ou remplacer une exception") {
            Toggle("Cibler un membre", isOn: $memberTarget).onChange(of: memberTarget) { _, _ in target = "" }
            Picker("Cible", selection: $target) {
                Text("Choisir…").tag("")
                if memberTarget {
                    ForEach(workspace.guildMembers, id: \.userId) { Text($0.username).tag($0.userId) }
                } else {
                    ForEach(workspace.roles, id: \.id) { Text($0.name).tag($0.id) }
                }
            }
            PermissionEditor(title: "Autoriser", value: $allow)
            PermissionEditor(title: "Refuser", value: $deny)
            Button("Enregistrer l’exception") {
                let roleID = memberTarget ? nil : target
                let memberID = memberTarget ? target : nil
                let allowed = allow
                let denied = deny
                Task {
                    _ = await model.performBackend { _ = try $0.putOverride(channelId: channelID, roleId: roleID, memberId: memberID, allow: allowed, deny: denied) }
                    await model.loadOverrides()
                }
            }.disabled(target.isEmpty)
        }
    }
}

private struct PermissionEditor: View {
    let title: String
    @Binding var value: Int64
    var readOnly = false
    private let options: [(Int64, String)] = [(1, "Voir le salon"), (2, "Envoyer des messages"),
        (4, "Gérer les messages"), (8, "Gérer les salons"), (16, "Gérer les rôles"),
        (32, "Expulser des membres"), (64, "Bannir des membres")]

    var body: some View {
        DisclosureGroup(title) {
            ForEach(options, id: \.0) { bit, label in
                Toggle(label, isOn: Binding(get: { value & bit != 0 }, set: { value = $0 ? value | bit : value & ~bit })).disabled(readOnly)
            }
        }
    }
}
