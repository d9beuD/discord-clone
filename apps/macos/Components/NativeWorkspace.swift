import AppKit
import SwiftUI

/// One native split controller avoids competing minimum-size probes in nested SwiftUI splits.
struct NativeWorkspace: NSViewControllerRepresentable {
    let model: AppViewModel
    @Binding var showSidebar: Bool
    @Binding var showMembers: Bool
    let openSettings: () -> Void

    func makeNSViewController(context: Context) -> WorkspaceSplitController {
        let controller = WorkspaceSplitController()
        controller.openSettings = openSettings
        let sidebar = NSHostingController(rootView: HStack(spacing: 0) {
            ServerSidebar().frame(width: 80)
            Divider()
            ChannelSidebar()
        }.environment(model))
        let chat = NSHostingController(rootView: ChatView().environment(model))
        let members = NSHostingController(rootView: MemberSidebar().environment(model))
        // Pane widths belong to AppKit; SwiftUI measures only content inside each pane.
        sidebar.sizingOptions = []
        chat.sizingOptions = []
        members.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 400
        sidebarItem.preferredThicknessFraction = 240.0 / 1180
        let chatItem = NSSplitViewItem(viewController: chat)
        chatItem.minimumThickness = 360
        let membersItem = NSSplitViewItem(inspectorWithViewController: members)
        membersItem.minimumThickness = 220
        membersItem.maximumThickness = 360
        membersItem.preferredThicknessFraction = 260.0 / 1180
        membersItem.canCollapseFromWindowResize = true
        for item in [sidebarItem, membersItem] {
            item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            item.holdingPriority = NSLayoutConstraint.Priority(251)
            item.allowsFullHeightLayout = true
        }
        sidebarItem.isCollapsed = !showSidebar
        membersItem.isCollapsed = !showMembers
        controller.splitView.isVertical = true
        controller.addSplitViewItem(sidebarItem)
        controller.addSplitViewItem(chatItem)
        controller.addSplitViewItem(membersItem)
        controller.observePresentation(sidebar: $showSidebar, members: $showMembers)
        return controller
    }

    static func dismantleNSViewController(_ controller: WorkspaceSplitController, coordinator: ()) {
        controller.removeToolbar()
    }

    func updateNSViewController(_ controller: WorkspaceSplitController, context: Context) {
        controller.setPresentation(sidebar: showSidebar, members: showMembers)
    }
}

final class WorkspaceSplitController: NSSplitViewController, NSToolbarDelegate {
    var openSettings: (() -> Void)?
    private weak var toolbarWindow: NSWindow?
    private let nativeToolbar = NSToolbar(identifier: "workspace")
    private static let sidebarItem = NSToolbarItem.Identifier("workspace.sidebar-toggle")
    private static let membersItem = NSToolbarItem.Identifier("workspace.members-toggle")
    private static let demoItem = NSToolbarItem.Identifier("workspace.demo")
    private static let settingsItem = NSToolbarItem.Identifier("workspace.settings")

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = view.window, window.toolbar !== nativeToolbar else { return }
        window.styleMask.insert(.fullSizeContentView)
        nativeToolbar.delegate = self
        nativeToolbar.displayMode = .iconOnly
        toolbarWindow = window
        window.toolbar = nativeToolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarItem, .sidebarTrackingSeparator, .flexibleSpace, Self.demoItem,
         .flexibleSpace, .inspectorTrackingSeparator, Self.membersItem, Self.settingsItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == .sidebarTrackingSeparator || id == .inspectorTrackingSeparator {
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitView,
                                                  dividerIndex: id == .sidebarTrackingSeparator ? 0 : 1)
        }
        let item = NSToolbarItem(itemIdentifier: id)
        if id == Self.sidebarItem || id == Self.membersItem {
            let sidebar = id == Self.sidebarItem
            item.label = sidebar ? "Barre latérale" : "Membres"
            let button = NSButton(image: NSImage(systemSymbolName: sidebar ? "sidebar.left" : "sidebar.right",
                                                accessibilityDescription: item.label)!,
                                  target: self, action: sidebar ? #selector(toggleSidebar(_:)) : #selector(toggleInspector(_:)))
            button.bezelStyle = .toolbar
            button.setButtonType(.toggle)
            button.setAccessibilityIdentifier(id.rawValue)
            item.autovalidates = false
            item.view = button
            configureToggle(button, index: sidebar ? 0 : 2)
        } else if id == Self.demoItem {
            let label = NSTextField(labelWithString: "Mode démo")
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.toolTip = "Les messages restent en mémoire jusqu’à la fermeture de la session."
            item.view = label
            item.label = "Mode démo"
        } else if id == Self.settingsItem {
            item.label = "Paramètres"
            let button = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Paramètres")!,
                                  target: self, action: #selector(showSettings))
            button.isBordered = false
            button.setAccessibilityIdentifier("workspace.settings")
            item.view = button
        }
        return item
    }

    private func configureToggle(_ button: NSButton, index: Int) {
        let visible = !splitViewItems[index].isCollapsed
        let label = "\(visible ? "Masquer" : "Afficher") \(index == 0 ? "la barre latérale" : "les membres")"
        button.state = visible ? .on : .off
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    @objc private func showSettings() { openSettings?() }

    func removeToolbar() {
        if let window = toolbarWindow, window.toolbar === nativeToolbar { window.toolbar = nil }
        toolbarWindow = nil
    }

    private var presentationObservations: [NSKeyValueObservation] = []
    private var applyingPresentation = false

    func setPresentation(sidebar: Bool, members: Bool) {
        applyingPresentation = true
        splitViewItems[0].isCollapsed = !sidebar
        splitViewItems[2].isCollapsed = !members
        applyingPresentation = false
        for (id, index) in [(Self.sidebarItem, 0), (Self.membersItem, 2)] {
            if let button = nativeToolbar.items.first(where: { $0.itemIdentifier == id })?.view as? NSButton {
                configureToggle(button, index: index)
            }
        }
    }

    func observePresentation(sidebar: Binding<Bool>, members: Binding<Bool>) {
        for (index, binding) in [(0, sidebar), (2, members)] {
            let item = splitViewItems[index]
            presentationObservations.append(item.observe(\.isCollapsed, options: [.new]) { [weak self] _, change in
                let presented = !(change.newValue ?? true)
                // Native menu commands and divider/window resizing also change presentation.
                MainActor.assumeIsolated {
                    guard let self, !self.applyingPresentation else { return }
                    Task { @MainActor [weak self] in
                        guard self?.splitViewItems[index].isCollapsed == !presented else { return }
                        if binding.wrappedValue != presented { binding.wrappedValue = presented }
                    }
                }
            })
        }
    }
}
