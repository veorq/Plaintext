import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var document: DocumentController
    @EnvironmentObject private var interface: InterfaceState
    @State private var didRequestFullscreen = false

    private var palette: ThemePalette { settings.theme.palette }

    var body: some View {
        ZStack {
            Color(nsColor: palette.background).ignoresSafeArea()

            VStack(spacing: 0) {
                Text(document.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: palette.secondary).opacity(0.8))
                    .lineLimit(1)
                    .padding(.top, 17)

                EditorTextView(
                    text: Binding(get: { document.text }, set: { document.setText($0) }),
                    settings: settings,
                    onFind: { interface.showingFind = true },
                    onCommandPalette: { interface.showingCommandPalette = true },
                    onSettings: { interface.showingSettings = true },
                    onUndo: { document.undo() },
                    onRedo: { document.redo() },
                    onEditorReady: { document.attachEditor($0) }
                )
                .frame(maxWidth: 760, maxHeight: .infinity)
                .padding(.horizontal, 28)
            }

            VStack {
                if interface.showingFind {
                    FindReplaceBar(onDismiss: {
                        interface.showingFind = false
                        document.focusEditor()
                    })
                    .padding(.top, 43)
                }
                Spacer()
                HStack {
                    Spacer()
                    if settings.showsWordCount {
                        Text(wordCountLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(nsColor: palette.secondary))
                    }
                }
                .padding(.horizontal, 25)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .onAppear {
            document.showAlert = { interface.alertMessage = $0 }
            requestFullscreenOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { document.focusEditor() }
        }
        .onChange(of: document.displayTitle) { _, title in
            NSApplication.shared.keyWindow?.title = title
        }
        .sheet(isPresented: $interface.showingSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $interface.showingHistory) {
            HistoryView()
                .environmentObject(document)
                .environmentObject(interface)
        }
        .overlay {
            if interface.showingCommandPalette {
                CommandPalette(onDismiss: {
                    interface.showingCommandPalette = false
                    document.focusEditor()
                })
                .environmentObject(settings)
                .environmentObject(document)
                .environmentObject(interface)
            }
        }
        .alert("Plaintext", isPresented: Binding(
            get: { interface.alertMessage != nil },
            set: { if !$0 { interface.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { interface.alertMessage = nil }
        } message: {
            Text(interface.alertMessage ?? "")
        }
    }

    private var wordCountLabel: String {
        let count = document.text.split(whereSeparator: { $0.isWhitespace }).count
        return "\(count) \(count == 1 ? "word" : "words")"
    }

    private func requestFullscreenOnce() {
        guard !didRequestFullscreen else { return }
        didRequestFullscreen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard let window = NSApplication.shared.windows.first, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }
}

private struct FindReplaceBar: View {
    @EnvironmentObject private var document: DocumentController
    @EnvironmentObject private var settings: AppSettings
    @State private var search = ""
    @State private var replacement = ""
    @FocusState private var focusedField: Field?
    let onDismiss: () -> Void

    private enum Field { case search, replacement }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $search)
                .textFieldStyle(.plain)
                .frame(width: 155)
                .focused($focusedField, equals: .search)
                .onSubmit { document.showNextMatch(for: search) }
            TextField("Replace", text: $replacement)
                .textFieldStyle(.plain)
                .frame(width: 155)
                .focused($focusedField, equals: .replacement)
                .onSubmit { document.replaceCurrentMatch(search: search, with: replacement) }
            Button("Next") { document.showNextMatch(for: search) }
            Button("Replace") { document.replaceCurrentMatch(search: search, with: replacement) }
            Button("All") { document.replaceAll(search: search, with: replacement) }
            Button("×") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color(nsColor: settings.theme.palette.foreground))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: settings.theme.palette.background).opacity(0.98))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: settings.theme.palette.secondary).opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(settings.theme.isDark ? 0.35 : 0.12), radius: 20, y: 8)
        .onAppear { focusedField = .search }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Settings")
                    .font(.system(size: 21, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 9) {
                SettingLabel("Theme")
                HStack(spacing: 8) {
                    ForEach(EditorTheme.allCases) { theme in
                        Button {
                            settings.theme = theme
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color(nsColor: theme.palette.background))
                                    .overlay(Circle().stroke(Color(nsColor: theme.palette.foreground).opacity(0.38), lineWidth: settings.theme == theme ? 2 : 0.7))
                                    .frame(width: 27, height: 27)
                                Text(theme.name).font(.system(size: 10))
                            }
                            .foregroundStyle(.primary)
                            .frame(width: 54)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                SettingLabel("Typeface")
                Picker("Typeface", selection: $settings.font) {
                    ForEach(FontChoice.allCases) { font in
                        Text("\(font.name)  ·  \(font.family)").tag(font)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320, alignment: .leading)
            }

            Toggle("Key sound", isOn: keySoundEnabled)
            Toggle("Show word count", isOn: $settings.showsWordCount)
            Spacer()
        }
        .padding(28)
        .frame(width: 460, height: 410)
    }

    private var keySoundEnabled: Binding<Bool> {
        Binding(
            get: { settings.typewriterSound == .soft },
            set: { settings.typewriterSound = $0 ? .soft : .off }
        )
    }
}

private struct SettingLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var document: DocumentController
    @EnvironmentObject private var interface: InterfaceState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Earlier Versions")
                .font(.system(size: 21, weight: .semibold))
            Text("Automatic local snapshots. Restoring one replaces the current document and is saved as a new version.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if document.history.isEmpty {
                Spacer()
                Text("No earlier versions yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(document.history) { snapshot in
                    Button {
                        document.restore(snapshot: snapshot)
                        dismiss()
                    } label: {
                        HStack {
                            Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text("Restore")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 410)
    }
}

private struct CommandPalette: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var document: DocumentController
    @EnvironmentObject private var interface: InterfaceState
    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    let onDismiss: () -> Void

    private struct PaletteAction: Identifiable {
        let id = UUID()
        let title: String
        let shortcut: String
        let action: () -> Void
    }

    private var actions: [PaletteAction] {
        [
            PaletteAction(title: "Open document", shortcut: "⌘O") { document.openDocumentPanel() },
            PaletteAction(title: "Save as", shortcut: "⇧⌘S") { document.saveAs() },
            PaletteAction(title: "Find and replace", shortcut: "⌘F") { interface.showingFind = true },
            PaletteAction(title: "Restore earlier version", shortcut: "⇧⌘H") { interface.showingHistory = true },
            PaletteAction(title: settings.showsWordCount ? "Hide word count" : "Show word count", shortcut: "") { settings.showsWordCount.toggle() },
            PaletteAction(title: "Settings", shortcut: "⌘,") { interface.showingSettings = true },
            PaletteAction(title: "Toggle fullscreen", shortcut: "⌃⌘F") { NSApplication.shared.keyWindow?.toggleFullScreen(nil) }
        ]
    }

    private var filteredActions: [PaletteAction] {
        guard !query.isEmpty else { return actions }
        return actions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                TextField("Type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(16)
                    .focused($fieldFocused)
                    .onSubmit { runFirstAction() }

                Divider()

                VStack(spacing: 0) {
                    ForEach(filteredActions) { item in
                        Button {
                            item.action()
                            onDismiss()
                        } label: {
                            HStack {
                                Text(item.title)
                                Spacer()
                                Text(item.shortcut)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 5)
            }
            .frame(width: 410)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.26), radius: 28, y: 12)
        }
        .onAppear { fieldFocused = true }
        .onExitCommand(perform: onDismiss)
    }

    private func runFirstAction() {
        guard let item = filteredActions.first else { return }
        item.action()
        onDismiss()
    }
}
