import AppKit
import SwiftUI

@main
struct DiscordCloneApp: App {
    @State private var model = AppViewModel()
    @AppStorage("appearance", store: AppPreferences.store) private var appearance = "system"

    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            AppPreferences.store.removePersistentDomain(forName: AppPreferences.testDomain)
            AppPreferences.store.set(ProcessInfo.processInfo.environment["UITEST_APPEARANCE"] ?? "light", forKey: "appearance")
        }
    }

    var body: some Scene {
        Window("Discord Clone", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.closeSession()
                }
                .onDisappear { model.closeSession() }
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .sidebar) {
                Button(model.showSidebar ? "Masquer la barre latérale" : "Afficher la barre latérale") {
                    model.showSidebar.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(!model.isDemoOpen)
            }
            CommandMenu("Serveurs") {
                ForEach(Array(model.servers.enumerated()), id: \.element.id) { index, server in
                    Button(server.name) { model.selectServer(server.id) }
                        .keyboardShortcut(index < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command) : nil)
                }
            }
            CommandGroup(after: .sidebar) {
                Button(model.showMembers ? "Masquer les membres" : "Afficher les membres") {
                    model.showMembers.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!model.isDemoOpen)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

@MainActor
enum AppPreferences {
    static let testDomain = "dev.discordclone.macos.UITests"
    static let store: UserDefaults = {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return UserDefaults(suiteName: testDomain)!
        }
        return .standard
    }()
}

private struct RootView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        Group {
            if model.isDemoOpen {
                WorkspaceView()
            } else {
                LoginView()
            }
        }
        .background(MinimumWindowSize())
    }
}

@MainActor
private protocol WindowHostingSizing: AnyObject {
    var sizingOptions: NSHostingSizingOptions { get set }
}

extension NSHostingView: WindowHostingSizing {}

/// Keep window bounds independent of SwiftUI's nested split-view size probes.
struct MinimumWindowSize: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowSizingView { WindowSizingView() }
    func updateNSView(_ view: WindowSizingView, context: Context) { view.configureWindow() }
}

final class WindowSizingView: NSView {
    private var resizeDelegate: MinimumSizeDelegate?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        if let host = window.contentView as? any WindowHostingSizing, !host.sizingOptions.isEmpty {
            host.sizingOptions = []
        }
        guard window.delegate !== resizeDelegate || resizeDelegate == nil else { return }
        let delegate = MinimumSizeDelegate(previous: window.delegate)
        resizeDelegate = delegate
        window.delegate = delegate
    }
}

@MainActor
private final class MinimumSizeDelegate: NSObject, NSWindowDelegate {
    // Objective-C capability queries are nonisolated; this weak reference is set only during initialization.
    nonisolated(unsafe) private weak var previous: (any NSWindowDelegate)?

    init(previous: (any NSWindowDelegate)?) { self.previous = previous }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let proposed = previous?.windowWillResize?(sender, to: frameSize) ?? frameSize
        let minimum = sender.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 900, height: 600)).size
        return NSSize(width: max(minimum.width, proposed.width), height: max(minimum.height, proposed.height))
    }

    override nonisolated func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || previous?.responds(to: selector) == true
    }

    override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
        previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector)
    }
}
