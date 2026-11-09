import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NativeWorkspace(model: model, showSidebar: $model.showSidebar, showMembers: $model.showMembers, openSettings: { openSettings() })
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $model.showManagement) { CommunityManagementView().environment(model) }
        .sheet(isPresented: $model.showJoinServer) { JoinServerView().environment(model) }
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
                    .background(ServerTooltip(name: server.name))
                    .accessibilityLabel(server.name)
                    .accessibilityIdentifier("server.\(server.id)")
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.horizontal, 8, for: .scrollContent)
        .accessibilityLabel("Serveurs")
        .accessibilityIdentifier("navigation.servers")
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.isConnected {
                Button { model.showJoinServer = true } label: { Image(systemName: "plus.circle").font(.title2).padding(12) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Créer ou rejoindre un serveur")
                    .accessibilityIdentifier("workspace.addServer")
                    .disabled(model.isWorking)
            }
        }
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

private struct ServerTooltip: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> ServerTooltipAnchor { ServerTooltipAnchor() }
    func updateNSView(_ view: ServerTooltipAnchor, context: Context) { view.name = name }
    static func dismantleNSView(_ view: ServerTooltipAnchor, coordinator: ()) { view.hideTooltip() }
}

private struct ServerTooltipBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: rect.minX + 7, y: rect.minY,
            width: rect.width - 7, height: rect.height), cornerRadius: 8)
        path.move(to: CGPoint(x: rect.minX + 7, y: rect.midY - 5))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 7, y: rect.midY + 5))
        path.closeSubpath()
        return path
    }
}

private final class ServerTooltipAnchor: NSView {
    var name = ""
    private var tooltip: NSPanel?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideTooltip()
    }

    override func mouseEntered(with event: NSEvent) {
        guard tooltip == nil, let window, window.isKeyWindow else { return }
        let content = NSHostingView(rootView: Text(name)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.leading, 7)
            .background(.regularMaterial, in: ServerTooltipBubble())
            .fixedSize()
            .accessibilityIdentifier("server.tooltip"))
        let size = content.fittingSize
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let panel = NSPanel(contentRect: NSRect(x: anchor.maxX + 8, y: anchor.midY - size.height / 2,
            width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.contentView = content
        panel.appearance = window.effectiveAppearance
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        tooltip = panel
    }

    override func mouseExited(with event: NSEvent) { hideTooltip() }

    func hideTooltip() {
        guard let tooltip else { return }
        tooltip.parent?.removeChildWindow(tooltip)
        tooltip.close()
        self.tooltip = nil
    }
}
