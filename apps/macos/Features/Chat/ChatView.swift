import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let channel = model.selectedChannel {
                HStack(spacing: 12) {
                    Image(systemName: "number").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name).font(.headline)
                        Text(channel.topic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .accessibilityIdentifier("chat.header")
                Divider()
                if let error = model.errorMessage {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                        Spacer()
                        Button("Réessayer") { model.retry() }
                    }
                    .padding(12)
                    .background(.orange.opacity(0.1))
                    .accessibilityIdentifier("chat.error")
                }
                conversation(channel: channel)
                ComposerView()
            } else {
                ContentUnavailableView("Choisissez un salon", systemImage: "bubble.left.and.bubble.right", description: Text("Vos conversations apparaîtront ici."))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func conversation(channel: Channel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "number.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text("Bienvenue dans #\(channel.name)")
                            .font(.title2.weight(.semibold))
                        Text(model.messages.isEmpty ? "Le début d’une nouvelle conversation. Envoyez le premier message." : "C’est ici que commence cette conversation.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 18)
                    .accessibilityIdentifier("chat.welcome")
                    ForEach(model.messages, id: \.id) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
            }
            .accessibilityIdentifier("chat.messages")
            .onChange(of: model.selectedChannelID) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: model.messages.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

private struct MessageRow: View {
    let message: Message
    @Environment(AppViewModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.profile = message.author } label: { AvatarView(user: message.author) }
                .buttonStyle(.plain)
                .accessibilityLabel("Profil de \(message.author.displayName)")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(message.author.displayName).font(.callout.weight(.semibold))
                    Text(Date(timeIntervalSince1970: Double(message.createdAtMs) / 1000), format: .dateTime.day().month().hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(message.content)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("message.content.\(message.id)")
            }
            .accessibilityElement(children: .contain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copier le message", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            }
            if message.author.id == model.currentUser?.id {
                Button("Supprimer le message", systemImage: "trash", role: .destructive) { model.deleteMessage(message) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ComposerView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                MessageEditor(
                    text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                    placeholder: "Message dans #\(model.selectedChannel?.name ?? "salon")",
                    channelID: model.selectedChannelID,
                    onSubmit: { model.sendMessage() }
                )
                .frame(height: 64)
                Button { model.sendMessage() } label: {
                    Image(systemName: "arrow.up").fontWeight(.semibold)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!model.canSend)
                .accessibilityLabel("Envoyer le message")
                .accessibilityIdentifier("chat.send")
                .help("Envoyer (Entrée)")
                .padding(.bottom, 6)
            }
            .padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.6)))
            HStack {
                Text("Entrée pour envoyer · Maj+Entrée pour une nouvelle ligne")
                Spacer()
                Text("Démo locale")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }
}
