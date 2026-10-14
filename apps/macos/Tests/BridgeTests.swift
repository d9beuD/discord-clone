import XCTest
import AppKit
import SwiftUI
@testable import DiscordClone

final class BridgeTests: XCTestCase {
    func testDemoUsesRealRustAndPreservesUnicode() throws {
        let client = try ChatClient.newDemo()
        defer { client.close() }
        XCTAssertEqual(try client.listServers().count, 3)
        XCTAssertEqual(try client.currentUser().id, "you")
        XCTAssertTrue(try client.listMessages(channelId: "ideas").isEmpty)
        let content = "Bonjour 🦀\nこんにちは\nDeuxième ligne"
        let sent = try client.sendMessage(channelId: "ideas", content: content)
        XCTAssertEqual(sent.content, content)
        XCTAssertEqual(try client.listMessages(channelId: "ideas").map(\.id), [sent.id])
        XCTAssertEqual(try client.listMessages(channelId: "general").count, 4)
        XCTAssertThrowsError(try client.sendMessage(channelId: "ideas", content: " \n\t")) { error in
            XCTAssertEqual(error as? ChatError, .EmptyContent)
        }
        XCTAssertThrowsError(try client.deleteMessage(channelId: "general", messageId: "seed-1")) { error in
            XCTAssertEqual(error as? ChatError, .DeletionForbidden)
        }
        try client.deleteMessage(channelId: "ideas", messageId: sent.id)
        XCTAssertTrue(try client.listMessages(channelId: "ideas").isEmpty)
    }

    func testEventsSeeCommittedStorageAndStopAfterUnsubscribe() async throws {
        let client = try ChatClient.newDemo()
        defer { client.close() }
        let received = expectation(description: "Rust dispatches event from background worker")
        let noEvent = expectation(description: "No event after unsubscribe")
        noEvent.isInverted = true
        let listener = ProbeListener(client: client, received: received, unexpected: noEvent)
        try client.setEventListener(listener: listener)
        _ = try client.sendMessage(channelId: "ideas", content: "event")
        await fulfillment(of: [received], timeout: 2)
        try client.clearEventListener()
        _ = try client.sendMessage(channelId: "ideas", content: "silent")
        await fulfillment(of: [noEvent], timeout: 0.15)
        XCTAssertTrue(listener.observedCommittedMessage)
        XCTAssertTrue(listener.observedBackgroundThread)
    }

    func testSessionClosureAndFreshSession() throws {
        let first = try ChatClient.newDemo()
        _ = try first.sendMessage(channelId: "ideas", content: "temporary")
        first.close()
        first.close()
        XCTAssertThrowsError(try first.listServers()) { error in
            XCTAssertEqual(error as? ChatError, .SessionClosed)
        }
        let second = try ChatClient.newDemo()
        defer { second.close() }
        XCTAssertTrue(try second.listMessages(channelId: "ideas").isEmpty)
    }

    @MainActor
    func testViewModelDeduplicatesAndKeepsDraftsPerChannel() async throws {
        let model = AppViewModel()
        await model.openDemo()
        defer { model.closeSession() }
        XCTAssertTrue(model.isDemoOpen)
        XCTAssertEqual(model.selectedChannelID, "general")
        model.selectChannel("ideas")
        model.draft = "A local message"
        model.sendMessage()
        let message = try XCTUnwrap(model.messages.first)
        model.apply(.messageReceived(message: message))
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.draft, "")
        model.draft = "Keep this draft"
        model.selectChannel("design")
        model.draft = "Another draft"
        model.selectChannel("ideas")
        XCTAssertEqual(model.draft, "Keep this draft")
        model.selectServer("rust")
        model.selectServer("atelier")
        XCTAssertEqual(model.selectedChannelID, "ideas")
        model.deleteMessage(message)
        model.apply(.messageDeleted(channelId: "ideas", messageId: message.id))
        XCTAssertTrue(model.messages.isEmpty)
        model.closeSession()
        await Task.yield()
        XCTAssertFalse(model.isDemoOpen)
        XCTAssertTrue(model.messages.isEmpty)
    }

    @MainActor
    func testRepeatedWindowResizingWithBothNativePanels() async throws {
        let model = AppViewModel()
        await model.openDemo()
        defer { model.closeSession() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "resize-regression")
        let originalDelegate = ResizeDelegateProbe()
        window.delegate = originalDelegate
        let host = NSHostingView(rootView: WorkspaceView().environment(model).background(MinimumWindowSize()))
        window.contentView = host
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.sizingOptions, [])
        let clamped = try XCTUnwrap(window.delegate?.windowWillResize?(window,
            to: NSSize(width: 700, height: 400)))
        XCTAssertEqual(clamped.width, 900)
        XCTAssertGreaterThanOrEqual(clamped.height, 600)
        XCTAssertFalse(try XCTUnwrap(window.delegate?.windowShouldClose?(window)))
        func splitViews(in view: NSView) -> [NSSplitView] {
            ((view as? NSSplitView).map { [$0] } ?? [])
                + view.subviews.flatMap { splitViews(in: $0) }
        }
        let splits = splitViews(in: host)
        let split = try XCTUnwrap(splits.first)
        XCTAssertEqual(splits.count, 1)
        let controller = try XCTUnwrap(split.delegate as? WorkspaceSplitController)
        XCTAssertEqual(controller.splitViewItems.count, 3)
        let inspectorToggle = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "workspace.members-toggle" })
        let inspectorButton = try XCTUnwrap(inspectorToggle.view as? NSButton)
        XCTAssertTrue(inspectorButton.target === controller)
        inspectorToggle.validate()
        XCTAssertTrue(inspectorButton.isEnabled)
        inspectorButton.performClick(nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(model.showMembers)
        inspectorButton.performClick(nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(model.showMembers)
        XCTAssertTrue(controller.splitViewItems[2].allowsFullHeightLayout)
        split.setPosition(400, ofDividerAt: 0)
        split.setPosition(host.bounds.width - 360, ofDividerAt: 1)
        for cycle in 0..<20 {
            window.setContentSize(NSSize(width: 900, height: 600))
            model.showMembers = false
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            controller.toggleSidebar(nil)
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(model.showSidebar)
            controller.toggleSidebar(nil)
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(model.showSidebar)
            model.showMembers = true
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.width, 900, accuracy: 1, "Panel cycle \(cycle) must not grow the window")
            XCTAssertEqual(window.frame.height, 600, accuracy: 1)
            XCTAssertGreaterThanOrEqual(controller.splitViewItems[1].viewController.view.frame.width, 360)
        }
        XCTAssertGreaterThan(originalDelegate.resizeCalls, 0)
        controller.removeToolbar()
        XCTAssertNil(window.toolbar)
    }

    @MainActor
    func testNativeLayoutsRenderAtWideAndCompactWidths() async throws {
        let model = AppViewModel()
        await model.openDemo()
        defer { model.closeSession() }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let destination = root.appendingPathComponent(".build/previews")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for (name, width, scheme) in [
            ("workspace-light", 1180.0, ColorScheme.light),
            ("workspace-dark", 1180.0, ColorScheme.dark),
            ("workspace-compact", 900.0, ColorScheme.light)
        ] {
            model.showMembers = true
            // Render an unshown native hosting window: no desktop automation is needed.
            let frame = NSRect(x: 0, y: 0, width: width, height: 740)
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: WorkspaceView().environment(model).preferredColorScheme(scheme))
            // Keep the requested snapshot viewport instead of resizing the unshown window to its ideal size.
            host.sizingOptions = []
            window.contentView = host
            host.frame = frame
            host.layoutSubtreeIfNeeded()
            // Native split views finish their initial layout on the next run-loop passes.
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            window.setContentSize(frame.size)
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertEqual(bitmap.pixelsWide, Int(width * host.window!.backingScaleFactor))
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: destination.appendingPathComponent(name + ".png"))
            window.close()
        }
    }
}

@MainActor
private final class ResizeDelegateProbe: NSObject, NSWindowDelegate {
    var resizeCalls = 0

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        resizeCalls += 1
        return frameSize
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
}

/// Protected probe state; no strong reference cycle because the client is weak.
private final class ProbeListener: ChatEventListener, @unchecked Sendable {
    private weak var client: ChatClient?
    private let lock = NSLock()
    private let received: XCTestExpectation
    private let unexpected: XCTestExpectation
    private var count = 0
    private var committed = false
    private var background = false

    init(client: ChatClient, received: XCTestExpectation, unexpected: XCTestExpectation) {
        self.client = client
        self.received = received
        self.unexpected = unexpected
    }

    var observedCommittedMessage: Bool { lock.withLock { committed } }
    var observedBackgroundThread: Bool { lock.withLock { background } }

    func onEvent(event: ChatEvent) throws {
        if case let .messageReceived(message) = event {
            let visible = try client?.listMessages(channelId: message.channelId).contains { $0.id == message.id } ?? false
            let isFirst = lock.withLock {
                count += 1
                committed = visible
                background = !Thread.isMainThread
                return count == 1
            }
            if isFirst { received.fulfill() } else { unexpected.fulfill() }
        }
    }
}
