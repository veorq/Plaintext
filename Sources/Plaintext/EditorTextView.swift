import AppKit
import SwiftUI

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    let settings: AppSettings
    let onFind: () -> Void
    let onCommandPalette: () -> Void
    let onSettings: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onEditorReady: (PlainTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = PlainTextView()
        textView.delegate = context.coordinator
        textView.editorDelegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.allowsUndo = false
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 22, height: 72)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 100, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        context.coordinator.textView = textView
        configure(textView, with: settings)
        context.coordinator.markConfigurationApplied(for: settings)
        scrollView.documentView = textView
        onEditorReady(textView)
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlainTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            context.coordinator.isSynchronising = true
            textView.replaceText(text)
            context.coordinator.isSynchronising = false
        }
        if context.coordinator.needsConfiguration(for: settings) {
            configure(textView, with: settings)
            context.coordinator.markConfigurationApplied(for: settings)
        }
    }

    private func configure(_ textView: PlainTextView, with settings: AppSettings) {
        let palette = settings.theme.palette
        let font = settings.font.nsFont(size: 19)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 10
        paragraph.paragraphSpacing = 0
        paragraph.lineBreakMode = .byWordWrapping

        textView.font = font
        textView.textColor = palette.foreground
        textView.backgroundColor = .clear
        textView.insertionPointColor = palette.foreground
        textView.selectedTextAttributes = [.backgroundColor: palette.selection, .foregroundColor: palette.foreground]
        textView.typingAttributes = [.font: font, .foregroundColor: palette.foreground, .paragraphStyle: paragraph]
        textView.defaultParagraphStyle = paragraph
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: PlainTextView?
        var isSynchronising = false
        private var appliedFont: FontChoice?
        private var appliedTheme: EditorTheme?

        init(parent: EditorTextView) {
            self.parent = parent
        }

        func needsConfiguration(for settings: AppSettings) -> Bool {
            appliedFont != settings.font || appliedTheme != settings.theme
        }

        func markConfigurationApplied(for settings: AppSettings) {
            appliedFont = settings.font
            appliedTheme = settings.theme
        }

        func textDidChange(_ notification: Notification) {
            guard !isSynchronising, let textView else { return }
            parent.text = textView.string
        }

        func openFind() {
            let callback = parent.onFind
            Task { @MainActor in callback() }
        }

        func openCommandPalette() {
            let callback = parent.onCommandPalette
            Task { @MainActor in callback() }
        }

        func openSettings() {
            let callback = parent.onSettings
            Task { @MainActor in callback() }
        }

        func performUndo() {
            let callback = parent.onUndo
            Task { @MainActor in callback() }
        }

        func performRedo() {
            let callback = parent.onRedo
            Task { @MainActor in callback() }
        }
    }
}

final class PlainTextView: NSTextView {
    weak var editorDelegate: EditorTextView.Coordinator?

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let textFont = font ?? NSFont.systemFont(ofSize: 19)
        let normalHeight = ceil(textFont.ascender - textFont.descender)
        let fixedRect = NSRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: min(rect.height, normalHeight)
        )
        super.drawInsertionPoint(in: fixedRect, color: color, turnedOn: flag)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if modifiers.contains(.command) {
            switch character {
            case "f": editorDelegate?.openFind(); return
            case "p" where modifiers.contains(.shift): editorDelegate?.openCommandPalette(); return
            case ",": editorDelegate?.openSettings(); return
            case "z" where modifiers.contains(.shift): editorDelegate?.performRedo(); return
            case "z": editorDelegate?.performUndo(); return
            default: break
            }
            super.keyDown(with: event)
            return
        }

        playTypewriterSoundIfAppropriate(event)
        super.keyDown(with: event)
    }

    func replaceText(_ value: String) {
        let oldRange = NSRange(location: 0, length: (string as NSString).length)
        shouldChangeText(in: oldRange, replacementString: value)
        textStorage?.replaceCharacters(in: oldRange, with: value)
        didChangeText()
    }

    private func playTypewriterSoundIfAppropriate(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.contains(.control), !modifiers.contains(.option), !modifiers.contains(.command), let style = editorDelegate?.parent.settings.typewriterSound else { return }
        if event.characters?.isEmpty == false || event.keyCode == 51 || event.keyCode == 36 {
            TypewriterSoundPlayer.shared.play(style)
        }
    }
}
