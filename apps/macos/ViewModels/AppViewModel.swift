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
    private(set) var isConnected = false
    private(set) var isWorking = false
    private(set) var workspace: BackendWorkspace?
    private(set) var channelAccess: ChannelAccess?
    private(set) var invites: [Invite] = []
    private(set) var overrides: [ChannelOverride] = []
    var createdInviteToken: String?
    var showManagement = false
    var showJoinServer = false
    var isSessionOpen: Bool { isDemoOpen || isConnected }
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
    @ObservationIgnored private var backend: BackendClient?
    @ObservationIgnored private var navigationTask: Task<Void, Never>?
    @ObservationIgnored private var navigationGeneration = 0
    @ObservationIgnored private var actionGeneration = 0
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
        isDemoOpen && selectedChannelID != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openDemo() async {
        guard !isLoading else { return }
        closeSession()
        isLoading = true
        errorMessage = nil
        let requestedGeneration = sessionGeneration
        defer { if requestedGeneration == sessionGeneration { isLoading = false } }
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
        if backend != nil {
            guard !isWorking else { return }
            navigationGeneration += 1
            let request = navigationGeneration
            navigationTask?.cancel()
            navigationTask = Task { await loadWorkspace(id, request: request) }
            return
        }
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
        if let backend {
            guard !isWorking, channels.contains(where: { $0.id == id }) else { return }
            navigationGeneration += 1
            let request = navigationGeneration
            let generation = sessionGeneration
            selectedChannelID = id
            channelAccess = nil
            overrides = []
            if let selectedServerID { lastChannelByServer[selectedServerID] = id }
            navigationTask?.cancel()
            navigationTask = Task {
                do {
                    let access = try await Task.detached { try backend.channelAccess(channelId: id) }.value
                    guard generation == sessionGeneration, request == navigationGeneration, !Task.isCancelled else { return }
                    channelAccess = access
                    errorMessage = nil
                } catch {
                    guard generation == sessionGeneration, request == navigationGeneration, !Task.isCancelled else { return }
                    handleBackendError(error)
                }
            }
            return
        }
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
        if backend != nil { Task { await refreshBackend() } }
        else if let selectedChannelID { selectChannel(selectedChannelID) }
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
        isLoading = false
        sessionGeneration += 1
        navigationGeneration += 1
        actionGeneration += 1
        navigationTask?.cancel()
        navigationTask = nil
        backend?.close()
        backend = nil
        isConnected = false
        isWorking = false
        workspace = nil
        channelAccess = nil
        invites = []
        overrides = []
        createdInviteToken = nil
        showManagement = false
        showJoinServer = false
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
        backend?.close()
        navigationTask?.cancel()
    }

    func authenticate(baseURL: String, email: String, password: String, username: String?) async {
        guard !isLoading else { return }
        closeSession()
        isLoading = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isLoading = false } }
        do {
            let backend = try await Task.detached {
                if let username {
                    return try BackendClient.register(baseUrl: baseURL, username: username, email: email, password: password)
                }
                return try BackendClient.login(baseUrl: baseURL, email: email, password: password)
            }.value
            guard generation == sessionGeneration, !Task.isCancelled else {
                // A canceled login still created a server session; revoke it off the UI thread.
                _ = await Task.detached { try? backend.logout() }.value
                return
            }
            self.backend = backend
            currentUser = backend.currentUser()
            isConnected = true
            isLoading = false
            await refreshBackend()
        } catch {
            guard generation == sessionGeneration else { return }
            handleBackendError(error)
        }
    }

    func refreshBackend(preferredServerID: String? = nil) async {
        guard let backend else { return }
        navigationGeneration += 1
        let request = navigationGeneration
        let generation = sessionGeneration
        do {
            let next = try await Task.detached { try backend.listServers() }.value
            guard generation == sessionGeneration, request == navigationGeneration, !Task.isCancelled else { return }
            servers = next
            let id = preferredServerID ?? selectedServerID
            if let server = next.first(where: { $0.id == id }) ?? next.first {
                await loadWorkspace(server.id, request: request)
            } else {
                clearWorkspace()
                errorMessage = nil
            }
        } catch {
            guard generation == sessionGeneration, request == navigationGeneration, !Task.isCancelled else { return }
            handleBackendError(error)
        }
    }

    /// Mutations never add or remove servers; skip the server-list fetch and reload only the selected workspace.
    func refreshWorkspace(preferredServerID: String? = nil) async {
        guard backend != nil, let id = preferredServerID ?? selectedServerID else {
            await refreshBackend()
            return
        }
        navigationGeneration += 1
        await loadWorkspace(id, request: navigationGeneration)
    }

    private func clearWorkspace() {
        workspace = nil
        channels = []
        members = []
        messages = []
        selectedServerID = nil
        selectedChannelID = nil
        channelAccess = nil
        invites = []
        overrides = []
        createdInviteToken = nil
    }

    private func loadWorkspace(_ id: String, request: Int) async {
        guard let backend else { return }
        let generation = sessionGeneration
        // Hide old controls immediately while the next server's permissions are loading.
        let remembered = lastChannelByServer[id]
        clearWorkspace()
        do {
            let next = try await Task.detached { try backend.workspace(guildId: id) }.value
            guard generation == sessionGeneration, request == navigationGeneration, !Task.isCancelled else { return }
            workspace = next
            selectedServerID = id
            channels = next.channels
            members = next.members
            selectedChannelID = (next.channels.first { $0.id == remembered } ?? next.channels.first)?.id
            errorMessage = nil
            if let channelID = selectedChannelID {
                let access = try await Task.detached { try backend.channelAccess(channelId: channelID) }.value
                guard generation == sessionGeneration, request == navigationGeneration, !Task.isCancelled else { return }
                channelAccess = access
            }
        } catch {
            guard generation == sessionGeneration, request == navigationGeneration, !Task.isCancelled else { return }
            handleBackendError(error)
        }
    }

    /// UI passes an intent; Rust validates, authorizes and performs it.
    func performBackend(_ operation: @escaping @Sendable (BackendClient) throws -> Void) async -> Bool {
        await performAction(operation) { _ in await self.refreshWorkspace() }
    }

    func performAction<T: Sendable>(
        _ operation: @escaping @Sendable (BackendClient) throws -> T,
        onSuccess: @escaping @MainActor @Sendable (T) async -> Void
    ) async -> Bool {
        guard let backend, !isWorking else { return false }
        isWorking = true
        let generation = sessionGeneration
        actionGeneration += 1
        let action = actionGeneration
        defer { if action == actionGeneration { isWorking = false } }
        do {
            let result = try await Task.detached { try operation(backend) }.value
            guard generation == sessionGeneration else { return false }
            errorMessage = nil
            await onSuccess(result)
            return generation == sessionGeneration && errorMessage == nil
        } catch {
            guard generation == sessionGeneration else { return false }
            handleBackendError(error)
            return false
        }
    }

    func createGuild(name: String) async -> Bool {
        await performAction({ try $0.createGuild(name: name) }) { guild in
            await self.refreshBackend(preferredServerID: guild.id)
        }
    }

    func acceptInvite(token: String) async -> Bool {
        await performAction({ try $0.acceptInvite(token: token) }) { guild in
            await self.refreshBackend(preferredServerID: guild.id)
        }
    }

    func loadInvites() async {
        guard let backend, let id = selectedServerID else { return }
        let generation = sessionGeneration
        let request = navigationGeneration
        do {
            let next = try await Task.detached { try backend.listInvites(guildId: id) }.value
            guard generation == sessionGeneration, request == navigationGeneration else { return }
            invites = next
        } catch {
            guard generation == sessionGeneration, request == navigationGeneration else { return }
            handleBackendError(error)
        }
    }

    func createInvite(expiresInSeconds: Int64?, maxUses: Int64?) async {
        guard let id = selectedServerID else { return }
        // No workspace refresh: loadWorkspace would clear the freshly created token.
        _ = await performAction({ try $0.createInvite(guildId: id, expiresInSeconds: expiresInSeconds, maxUses: maxUses) }) { created in
            self.createdInviteToken = created.token
            await self.loadInvites()
        }
    }

    func accessForChannel(_ id: String) async -> ChannelAccess? {
        guard let backend else { return nil }
        let generation = sessionGeneration
        do {
            let access = try await Task.detached { try backend.channelAccess(channelId: id) }.value
            guard generation == sessionGeneration else { return nil }
            return access
        } catch {
            guard generation == sessionGeneration else { return nil }
            handleBackendError(error)
            return nil
        }
    }

    func loadOverrides() async {
        guard let backend, let id = selectedChannelID, channelAccess?.canManageRoles == true else { return }
        let generation = sessionGeneration
        let request = navigationGeneration
        do {
            let next = try await Task.detached { try backend.listOverrides(channelId: id) }.value
            guard generation == sessionGeneration, request == navigationGeneration else { return }
            overrides = next
        } catch {
            guard generation == sessionGeneration, request == navigationGeneration else { return }
            handleBackendError(error)
        }
    }

    func logout() async {
        guard let backend else { closeSession(); return }
        // Detach local state immediately; remote revocation stays off the UI thread.
        self.backend = nil
        closeSession()
        let generation = sessionGeneration
        isLoading = true
        defer { if generation == sessionGeneration { isLoading = false } }
        do { try await Task.detached { try backend.logout() }.value }
        catch {
            guard generation == sessionGeneration else { return }
            errorMessage = "Session locale fermée ; révocation distante non confirmée. " + Self.describeBackend(error)
        }
    }

    private func handleBackendError(_ error: Error) {
        let description = Self.describeBackend(error)
        if let error = error as? BackendError {
            switch error {
            case .Http(status: 401, detail: _), .SessionClosed:
                closeSession()
                isLoading = false
            default: break
            }
        }
        errorMessage = description
    }

    static func describeBackend(_ error: Error) -> String {
        guard let error = error as? BackendError else { return "Impossible de terminer cette action. Réessayez." }
        switch error {
        case let .InvalidInput(detail), let .Http(_, detail): return detail
        case .Transport: return "Le serveur est inaccessible. Vérifiez son adresse et votre connexion."
        case .InvalidResponse: return "La réponse du serveur est invalide."
        case .SessionClosed: return "Votre session a expiré. Reconnectez-vous."
        }
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
