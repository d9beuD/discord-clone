import XCTest
import Darwin
import Foundation
import AppKit
import SwiftUI
@testable import DiscordClone

final class BackendTests: XCTestCase {
    @MainActor
    func testRealRustLoginLoadsCommunityWithoutBlockingMainActorAndLogoutResetsState() async throws {
        let fixture = try BackendFixture()
        defer { fixture.close() }
        let model = AppViewModel()
        let login = Task { await model.authenticate(baseURL: fixture.url, email: "u@example.invalid", password: "password", username: nil) }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.isLoading, "MainActor remains available while Rust waits for HTTP")
        await login.value
        XCTAssertTrue(model.isConnected)
        XCTAssertTrue(model.isSessionOpen)
        XCTAssertFalse(model.isDemoOpen)
        XCTAssertEqual(model.currentUser?.displayName, "Café 🦀")
        XCTAssertEqual(model.selectedServerID, BackendFixture.guildID)
        XCTAssertEqual(model.selectedChannelID, BackendFixture.channelID)
        XCTAssertEqual(model.channels.first?.name, "général")
        XCTAssertEqual(model.workspace?.remoteChannels.first?.kind, .voice)
        XCTAssertEqual(model.members.count, 1)
        XCTAssertEqual(model.workspace?.isOwner, true)
        XCTAssertEqual(model.channelAccess?.canManageRoles, true)
        model.draft = "This cannot be sent to an API without messages"
        XCTAssertFalse(model.canSend)
        model.sendMessage()
        XCTAssertTrue(model.messages.isEmpty)
        await model.logout()
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isSessionOpen)
        XCTAssertNil(model.currentUser)
        XCTAssertTrue(model.channels.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(fixture.requests.contains("POST /api/v1/auth/logout"))
        XCTAssertFalse(fixture.requests.contains { $0.contains("/messages") })
    }

    @MainActor
    func testClosedSessionCannotBeReopenedByPendingLogin() async throws {
        let fixture = try BackendFixture()
        defer { fixture.close() }
        let model = AppViewModel()
        let login = Task { await model.authenticate(baseURL: fixture.url, email: "u@example.invalid", password: "password", username: nil) }
        try await Task.sleep(for: .milliseconds(30))
        model.closeSession()
        await login.value
        XCTAssertFalse(model.isSessionOpen)
        XCTAssertNil(model.currentUser)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(fixture.requests.contains("POST /api/v1/auth/logout"), "Canceled login revokes its new server session")
    }

    @MainActor
    func testUnauthorizedClosesSessionAndOtherBackendErrorsPreserveIt() async throws {
        for (status, staysConnected) in [(401, false), (503, true)] {
            let fixture = try BackendFixture(guildStatus: status)
            let model = AppViewModel()
            await model.authenticate(baseURL: fixture.url, email: "u@example.invalid", password: "password", username: nil)
            XCTAssertEqual(model.isConnected, staysConnected)
            XCTAssertFalse(model.isDemoOpen)
            XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.errorMessage, "Fixture failure")
            model.closeSession()
            fixture.close()
        }
    }

    @MainActor
    func testMutationsRefetchOnlyWhatTheyChange() async throws {
        let fixture = try BackendFixture()
        defer { fixture.close() }
        let model = AppViewModel()
        await model.authenticate(baseURL: fixture.url, email: "u@example.invalid", password: "password", username: nil)
        defer { model.closeSession() }
        let renamed = await model.performBackend { _ = try $0.updateChannel(channelId: BackendFixture.channelID, name: "renommé", position: 0) }
        XCTAssertTrue(renamed)
        XCTAssertEqual(model.workspace?.remoteChannels.first?.name, "renommé")
        XCTAssertEqual(fixture.requests.filter { $0 == "GET /api/v1/guilds" }.count, 1, "a channel rename must not refetch the server list")
        XCTAssertEqual(fixture.requests.filter { $0 == "GET /api/v1/guilds/\(BackendFixture.guildID)/channels" }.count, 2, "login and rename each load the channels once")
        let revoked = await model.performAction({ try $0.revokeInvite(guildId: BackendFixture.guildID, inviteId: BackendFixture.inviteID) }) { _ in await model.loadInvites() }
        XCTAssertTrue(revoked)
        XCTAssertEqual(fixture.requests.filter { $0 == "GET /api/v1/guilds/\(BackendFixture.guildID)/invites" }.count, 1)
        XCTAssertEqual(fixture.requests.filter { $0 == "GET /api/v1/guilds/\(BackendFixture.guildID)/channels" }.count, 2, "revoking an invite must not refetch the workspace")
        XCTAssertEqual(model.errorMessage, nil)
    }

    @MainActor
    func testBackendAndLoginViewsRenderWithRealBridgeData() async throws {
        let fixture = try BackendFixture()
        defer { fixture.close() }
        let model = AppViewModel()
        await model.authenticate(baseURL: fixture.url, email: "u@example.invalid", password: "password", username: nil)
        defer { model.closeSession() }
        XCTAssertTrue(model.isConnected)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let destination = root.appendingPathComponent(".build/previews")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (name, view, size) in [
            ("backend-workspace", AnyView(WorkspaceView().environment(model)), NSSize(width: 1180, height: 740)),
            ("backend-management", AnyView(CommunityManagementView().environment(model)), NSSize(width: 680, height: 660)),
            ("backend-login", AnyView(LoginView().environment(AppViewModel())), NSSize(width: 900, height: 600))
        ] {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: view.preferredColorScheme(.light))
            host.sizingOptions = []
            window.contentView = host
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: destination.appendingPathComponent(name + ".png"))
            window.close()
        }
    }

    func testBackendBridgeRejectsInsecureURLsAndDescribesErrors() throws {
        XCTAssertThrowsError(try BackendClient.login(baseUrl: "http://example.com", email: "u@example.invalid", password: "password")) { error in
            guard case .InvalidInput = error as? BackendError else { return XCTFail("Expected Rust URL validation") }
        }
    }
}

/// Tiny local HTTP fixture; the app still executes its real Rust transport and generated FFI.
private final class BackendFixture: @unchecked Sendable {
    static let userID = "550e8400-e29b-41d4-a716-446655440000"
    static let guildID = "550e8400-e29b-41d4-a716-446655440001"
    static let channelID = "550e8400-e29b-41d4-a716-446655440002"
    static let inviteID = "550e8400-e29b-41d4-a716-446655440003"
    private var channelName = "général"
    private let socketFD: Int32
    private let guildStatus: Int
    private let lock = NSLock()
    private var recorded: [String] = []
    private var stopped = false
    let url: String
    var requests: [String] { lock.withLock { recorded } }

    init(guildStatus: Int = 200) throws {
        self.guildStatus = guildStatus
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        socketFD = fd
        guard fd >= 0 else { throw CocoaError(.fileReadUnknown) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0, listen(socketFD, 16) == 0 else { Darwin.close(socketFD); throw CocoaError(.fileReadUnknown) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        url = "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))"
        Thread.detachNewThread { [self] in
            while !lock.withLock({ stopped }) {
                let connection = accept(socketFD, nil, nil)
                if connection < 0 { break }
                respond(connection)
                Darwin.close(connection)
            }
        }
    }

    private var channelJSON: String {
        "{\"id\":\"\(Self.channelID)\",\"guild_id\":\"\(Self.guildID)\",\"kind\":\"voice\",\"name\":\"\(channelName)\",\"position\":0,\"created_at\":\"2026-10-14T10:00:00Z\"}"
    }

    func close() {
        let shouldClose = lock.withLock { if stopped { return false }; stopped = true; return true }
        if shouldClose { shutdown(socketFD, SHUT_RDWR); Darwin.close(socketFD) }
    }

    private func respond(_ connection: Int32) {
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) { setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size)) }
        var bytes = [UInt8](repeating: 0, count: 8192)
        let count = read(connection, &bytes, bytes.count)
        guard count > 0, let text = String(bytes: bytes.prefix(count), encoding: .utf8), let line = text.components(separatedBy: "\r\n").first else { return }
        let route = line.components(separatedBy: " ").prefix(2).joined(separator: " ")
        lock.withLock { recorded.append(route) }
        let user = "{\"id\":\"\(Self.userID)\",\"username\":\"Café 🦀\",\"email\":\"u@example.invalid\",\"created_at\":\"2026-10-14T10:00:00Z\"}"
        let guild = "{\"id\":\"\(Self.guildID)\",\"name\":\"Test server\",\"owner_id\":\"\(Self.userID)\",\"created_at\":\"2026-10-14T10:00:00Z\"}"
        let body: String
        var status = 200
        switch route {
        case "POST /api/v1/auth/login":
            Thread.sleep(forTimeInterval: 0.15)
            body = "{\"user\":\(user),\"token\":\"fixture-session\",\"token_type\":\"Bearer\",\"expires_at\":\"2026-10-15T10:00:00Z\"}"
        case "GET /api/v1/guilds":
            status = guildStatus
            body = status == 200 ? "[\(guild)]" : "{\"detail\":\"Fixture failure\"}"
        case "GET /api/v1/guilds/\(Self.guildID)": body = guild
        case "GET /api/v1/guilds/\(Self.guildID)/channels":
            body = "[\(channelJSON)]"
        case "PATCH /api/v1/channels/\(Self.channelID)":
            channelName = "renommé"
            body = channelJSON
        case "DELETE /api/v1/guilds/\(Self.guildID)/invites/\(Self.inviteID)":
            status = 204; body = ""
        case "GET /api/v1/guilds/\(Self.guildID)/invites":
            body = "[{\"id\":\"\(Self.inviteID)\",\"guild_id\":\"\(Self.guildID)\",\"creator_id\":\"\(Self.userID)\",\"created_at\":\"2026-10-14T10:00:00Z\",\"expires_at\":null,\"max_uses\":null,\"uses\":0,\"revoked_at\":null}]"
        case "GET /api/v1/guilds/\(Self.guildID)/members":
            body = "[{\"user_id\":\"\(Self.userID)\",\"username\":\"Café 🦀\",\"joined_at\":\"2026-10-14T10:00:00Z\",\"role_ids\":[]}]"
        case "GET /api/v1/guilds/\(Self.guildID)/roles":
            body = "[{\"id\":\"\(Self.guildID)\",\"guild_id\":\"\(Self.guildID)\",\"name\":\"@everyone\",\"permissions\":3,\"is_default\":true}]"
        case "GET /api/v1/channels/\(Self.channelID)/permissions/@me":
            body = "{\"channel_id\":\"\(Self.channelID)\",\"permissions\":127}"
        case "POST /api/v1/auth/logout": status = 204; body = ""
        default: status = 404; body = "{\"detail\":\"Unexpected fixture route\"}"
        }
        let data = Data("HTTP/1.1 \(status) Test\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8)
        data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = write(connection, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
                if count <= 0 { break }
                sent += count
            }
        }
    }
}
