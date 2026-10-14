import Foundation
import Observation

/// The relay only owns a thread-safe continuation, never the client or UI model.
final class EventRelay: ChatEventListener, Sendable {
    let continuation: AsyncStream<ChatEvent>.Continuation

    init(_ continuation: AsyncStream<ChatEvent>.Continuation) {
        self.continuation = continuation
    }

    func onEvent(event: ChatEvent) throws {
        continuation.yield(event)
    }
}

@Observable
@MainActor
final class AppViewModel {
    private(set) var isDemoOpen = false
    private(set) var isLoading = false
    private(set) var currentUser: User?
    private(set) var servers: [Server] = []
    private(set) var channels: [Channel] = []
    private(set) var messages: [Message] = []
    private(set) var members: [Member] = []
    private(set) var selectedServerID: String?
    private(set) var selectedChannelID: String?
    var showSidebar = true
    var showMembers = true
    var profile: User?
    var errorMessage: String?
    var drafts: [String: String] = [:]

    @ObservationIgnored private var client: ChatClient?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncStream<ChatEvent>.Continuation?
    @ObservationIgnored private var sessionGeneration = 0
    @ObservationIgnored private var lastChannelByServer: [String: String] = [:]

    var selectedServer: Server? { servers.first { $0.id == selectedServerID } }
    var selectedChannel: Channel? { channels.first { $0.id == selectedChannelID } }
    var draft: String {
        get { selectedChannelID.flatMap { drafts[$0] } ?? "" }
        set { if let id = selectedChannelID { drafts[id] = newValue } }
    }
    var canSend: Bool {
        selectedChannelID != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openDemo() async {
        guard !isLoading else { return }
        closeSession()
        isLoading = true
        errorMessage = nil
        let requestedGeneration = sessionGeneration
        defer { isLoading = false }
        await Task.yield()
        guard !Task.isCancelled, requestedGeneration == sessionGeneration else { return }
        do {
            let client = try ChatClient.newDemo()
            self.client = client
            currentUser = try client.currentUser()
            let (stream, continuation) = AsyncStream<ChatEvent>.makeStream()
            self.continuation = continuation
            try client.setEventListener(listener: EventRelay(continuation))
            let generation = sessionGeneration
            eventTask = Task { [weak self] in
                for await event in stream {
                    guard !Task.isCancelled, let self, self.sessionGeneration == generation else { break }
                    self.apply(event)
                }
            }
            servers = try client.listServers()
            if let first = servers.first { selectServer(first.id) }
            isDemoOpen = true
        } catch {
            closeSession()
            errorMessage = Self.describe(error)
        }
    }

    func selectServer(_ id: String) {
        guard let client else { return }
        do {
            let nextChannels = try client.listChannels(serverId: id)
            selectedServerID = id
            channels = nextChannels
            let remembered = lastChannelByServer[id]
            let next = nextChannels.first { $0.id == remembered } ?? nextChannels.first
            selectedChannelID = nil
            messages = []
            members = []
            if let next { selectChannel(next.id) }
        } catch { errorMessage = Self.describe(error) }
    }

    func selectChannel(_ id: String) {
        guard let client else { return }
        do {
            let nextMessages = try client.listMessages(channelId: id)
            let nextMembers = try client.listMembers(channelId: id)
            selectedChannelID = id
            if let selectedServerID { lastChannelByServer[selectedServerID] = id }
            messages = nextMessages
            members = nextMembers
            errorMessage = nil
        } catch { errorMessage = Self.describe(error) }
    }

    func sendMessage() {
        guard let client, let channelID = selectedChannelID, canSend else { return }
        do {
            let message = try client.sendMessage(channelId: channelID, content: draft)
            upsert(message)
            drafts[channelID] = ""
            errorMessage = nil
        } catch { errorMessage = Self.describe(error) }
    }

    func deleteMessage(_ message: Message) {
        guard let client else { return }
        do {
            try client.deleteMessage(channelId: message.channelId, messageId: message.id)
            messages.removeAll { $0.id == message.id }
            errorMessage = nil
        } catch { errorMessage = Self.describe(error) }
    }

    func retry() {
        errorMessage = nil
        if let selectedChannelID { selectChannel(selectedChannelID) }
    }

    func apply(_ event: ChatEvent) {
        switch event {
        case let .messageReceived(message):
            if message.channelId == selectedChannelID { upsert(message) }
        case let .messageDeleted(channelID, messageID):
            if channelID == selectedChannelID { messages.removeAll { $0.id == messageID } }
        case .userTyping:
            break // No typing simulation in the memory-only demo.
        }
    }

    private func upsert(_ message: Message) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    func closeSession() {
        sessionGeneration += 1
        eventTask?.cancel()
        eventTask = nil
        continuation?.finish()
        continuation = nil
        try? client?.clearEventListener()
        client?.close()
        client = nil
        isDemoOpen = false
        currentUser = nil
        servers = []
        channels = []
        messages = []
        members = []
        selectedServerID = nil
        selectedChannelID = nil
        drafts = [:]
        lastChannelByServer = [:]
        profile = nil
        errorMessage = nil
    }

    deinit {
        eventTask?.cancel()
        continuation?.finish()
        client?.close()
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? ChatError else { return "Impossible de terminer cette action. Réessayez." }
        switch error {
        case .EmptyContent: return "Écrivez un message avant de l’envoyer."
        case .DeletionForbidden: return "Vous pouvez supprimer uniquement vos propres messages."
        case .UnknownIdentifier: return "Ce salon ou ce message est introuvable."
        case .SessionClosed: return "La session est fermée. Rouvrez la démonstration."
        case .Internal: return "Une erreur interne est survenue. Réessayez."
        }
    }
}
