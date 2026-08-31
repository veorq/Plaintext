import AppKit
import SwiftUI

@main
struct PlaintextApp: App {
    @NSApplicationDelegateAdaptor(PlaintextAppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var document = DocumentController()
    @StateObject private var interface = InterfaceState()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Window("Plaintext", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(document)
                .environmentObject(interface)
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Plain Document") { document.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { document.openDocumentPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { document.save() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { document.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { document.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { document.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Writing") {
                Button("Find and Replace") {
                    interface.showingFind = true
                    document.focusEditor()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Restore Earlier Version…") { interface.showingHistory = true }
                    .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button(settings.showsWordCount ? "Hide Word Count" : "Show Word Count") {
                    settings.showsWordCount.toggle()
                }
            }

            CommandMenu("Plaintext") {
                Button("Command Palette…") { interface.showingCommandPalette = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Settings…") { interface.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button("Toggle Full Screen") { toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }

    private func toggleFullScreen() {
        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
    }
}

final class PlaintextAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FontChoice.registerBundledFonts()
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.windows.forEach { $0.tabbingMode = .disallowed }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
