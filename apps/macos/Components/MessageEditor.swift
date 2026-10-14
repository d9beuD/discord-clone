import AppKit
import SwiftUI

/// AppKit preserves native selection/IME while giving Return explicit chat semantics.
struct MessageEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let channelID: String?
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = ComposerTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .labelColor
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 5, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.placeholder = placeholder
        editor.setAccessibilityIdentifier("chat.editor")
        editor.setAccessibilityLabel("Message")
        editor.setAccessibilityHelp("Entrée pour envoyer. Maj+Entrée pour une nouvelle ligne.")
        let scroll = NSScrollView()
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self
        if editor.string != text { editor.string = text }
        editor.placeholder = placeholder
        editor.needsDisplay = true
        if context.coordinator.channelID != channelID {
            let shouldFocus = context.coordinator.channelID == nil || editor.window?.firstResponder === editor
            context.coordinator.channelID = channelID
            if shouldFocus {
                DispatchQueue.main.async { [weak editor] in
                    guard let editor else { return }
                    editor.window?.makeFirstResponder(editor)
                }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MessageEditor
        var channelID: String?
        init(_ parent: MessageEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            // Let input methods confirm their marked text before interpreting Return.
            if textView.hasMarkedText() { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertText("\n", replacementRange: textView.selectedRange())
            } else {
                parent.onSubmit()
            }
            return true
        }
    }
}

private final class ComposerTextView: NSTextView {
    var placeholder = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(
                at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]
            )
        }
    }
}
