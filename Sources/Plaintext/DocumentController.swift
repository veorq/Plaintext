import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class DocumentController: ObservableObject {
    @Published private(set) var text = ""
    @Published private(set) var documentURL: URL?
    @Published private(set) var displayTitle = "Untitled"
    @Published private(set) var history: [HistorySnapshot] = []

    weak var editor: PlainTextView?
    var showAlert: ((String) -> Void)?

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "plaintext.lastDocumentBookmark"
    private let recoveryName = "recovery.md"
    private var saveWorkItem: DispatchWorkItem?
    private var lastSnapshotText = ""
    private var undoSnapshots: [String] = []
    private var redoSnapshots: [String] = []
    private var lastUndoCheckpoint = Date.distantPast

    init() {
        restorePreviousSession()
    }

    var isUntitled: Bool { documentURL == nil }

    func setText(_ value: String, forceUndoCheckpoint: Bool = false) {
        guard value != text else { return }
        recordUndoCheckpoint(before: text, force: forceUndoCheckpoint)
        text = value
        schedulePersistence()
    }

    func attachEditor(_ textView: PlainTextView) {
        editor = textView
        if textView.string != text { textView.replaceText(text) }
        focusEditor()
    }

    func undo() {
        guard let previous = undoSnapshots.popLast() else { return }
        redoSnapshots.append(text)
        applyHistoryText(previous)
    }

    func redo() {
        guard let next = redoSnapshots.popLast() else { return }
        undoSnapshots.append(text)
        applyHistoryText(next)
    }

    func focusEditor() {
        editor?.window?.makeFirstResponder(editor)
    }

    func newDocument() {
        saveWorkItem?.cancel()
        documentURL = nil
        displayTitle = "Untitled"
        history = []
        text = ""
        lastSnapshotText = ""
        clearUndoHistory()
        defaults.removeObject(forKey: bookmarkKey)
        writeRecovery()
        focusEditor()
    }

    func openDocumentPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.message = "Open a Markdown or text document. It will replace the current document."
        if panel.runModal() == .OK, let url = panel.url {
            openDocument(at: url, remember: true)
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = documentURL?.lastPathComponent ?? "Untitled.md"
        panel.message = "Save as a plain Markdown document."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        documentURL = url
        displayTitle = url.lastPathComponent
        storeBookmark(for: url)
        persistNow()
        focusEditor()
    }

    func save() {
        if documentURL == nil {
            saveAs()
        } else {
            persistNow()
        }
    }

    func restore(snapshot: HistorySnapshot) {
        guard let restoredText = try? String(contentsOf: snapshot.url, encoding: .utf8) else {
            showAlert?("That earlier version is no longer available.")
            return
        }
        setText(restoredText, forceUndoCheckpoint: true)
        editor?.replaceText(restoredText)
        focusEditor()
    }

    func showNextMatch(for search: String) {
        guard !search.isEmpty, let editor else { return }
        let value = editor.string as NSString
        let start = min(editor.selectedRange().upperBound, value.length)
        let tail = NSRange(location: start, length: value.length - start)
        let found = value.range(of: search, options: [.caseInsensitive], range: tail)
        let match = found.location != NSNotFound ? found : value.range(of: search, options: [.caseInsensitive], range: NSRange(location: 0, length: value.length))
        guard match.location != NSNotFound else {
            showAlert?("No matches for “\(search)”.")
            return
        }
        editor.setSelectedRange(match)
        editor.scrollRangeToVisible(match)
    }

    func replaceCurrentMatch(search: String, with replacement: String) {
        guard let editor, !search.isEmpty else { return }
        let selected = editor.selectedRange()
        let selectedText = (editor.string as NSString).substring(with: selected)
        if selectedText.compare(search, options: [.caseInsensitive]) == .orderedSame {
            editor.insertText(replacement, replacementRange: selected)
        }
        showNextMatch(for: search)
    }

    func replaceAll(search: String, with replacement: String) {
        guard !search.isEmpty else { return }
        let updated = text.replacingOccurrences(of: search, with: replacement, options: [.caseInsensitive])
        guard updated != text else {
            showAlert?("No matches for “\(search)”.")
            return
        }
        setText(updated, forceUndoCheckpoint: true)
        editor?.replaceText(updated)
    }

    private func schedulePersistence() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persistNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func persistNow() {
        saveWorkItem?.cancel()
        if let documentURL {
            do {
                try withSecurityAccess(to: documentURL) {
                    try text.write(to: documentURL, atomically: true, encoding: .utf8)
                }
                writeSnapshotIfNeeded()
                try? FileManager.default.removeItem(at: recoveryURL)
            } catch {
                showAlert?("Plaintext could not save “\(documentURL.lastPathComponent)”.")
            }
        } else {
            writeRecovery()
        }
    }

    private func restorePreviousSession() {
        if let bookmark = defaults.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                openDocument(at: url, remember: false)
                return
            }
        }

        if let recovery = try? String(contentsOf: recoveryURL, encoding: .utf8), !recovery.isEmpty {
            text = recovery
        }
    }

    private func openDocument(at url: URL, remember: Bool) {
        do {
            let openedText = try withSecurityAccess(to: url) {
                try String(contentsOf: url, encoding: .utf8)
            }
            saveWorkItem?.cancel()
            documentURL = url
            displayTitle = url.lastPathComponent
            text = openedText
            lastSnapshotText = openedText
            clearUndoHistory()
            loadHistory()
            if remember { storeBookmark(for: url) }
            try? FileManager.default.removeItem(at: recoveryURL)
            editor?.replaceText(openedText)
            focusEditor()
        } catch {
            showAlert?("Plaintext could not open “\(url.lastPathComponent)”. Use UTF-8 plain text or Markdown.")
        }
    }

    private func storeBookmark(for url: URL) {
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    private func withSecurityAccess<T>(to url: URL, work: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try work()
    }

    private var supportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Plaintext", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var recoveryURL: URL { supportURL.appendingPathComponent(recoveryName) }

    private func writeRecovery() {
        try? text.write(to: recoveryURL, atomically: true, encoding: .utf8)
    }

    private var historyDirectory: URL? {
        guard let documentURL else { return nil }
        let stableID = String(fnv1a64(documentURL.standardizedFileURL.path), radix: 16)
        let url = supportURL.appendingPathComponent("History/\(stableID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSnapshotIfNeeded() {
        guard text != lastSnapshotText, let historyDirectory else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeDate = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let url = historyDirectory.appendingPathComponent("\(safeDate).md")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastSnapshotText = text
            loadHistory()
            let retained = history.dropFirst(80)
            for snapshot in retained { try? FileManager.default.removeItem(at: snapshot.url) }
            loadHistory()
        } catch {
            // Editing and saving must remain available even if history storage is unavailable.
        }
    }

    private func loadHistory() {
        guard let historyDirectory else {
            history = []
            return
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: historyDirectory, includingPropertiesForKeys: Array(keys))) ?? []
        history = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { return nil }
            return HistorySnapshot(url: url, date: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    private func fnv1a64(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private func recordUndoCheckpoint(before previous: String, force: Bool) {
        let now = Date()
        if force || now.timeIntervalSince(lastUndoCheckpoint) > 0.65 {
            if undoSnapshots.last != previous {
                undoSnapshots.append(previous)
                if undoSnapshots.count > 200 { undoSnapshots.removeFirst() }
            }
        }
        redoSnapshots.removeAll()
        lastUndoCheckpoint = now
    }

    private func applyHistoryText(_ value: String) {
        text = value
        editor?.replaceText(value)
        lastUndoCheckpoint = .distantPast
        schedulePersistence()
    }

    private func clearUndoHistory() {
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        lastUndoCheckpoint = .distantPast
    }
}
