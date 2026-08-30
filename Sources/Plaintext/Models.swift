import AppKit
import SwiftUI

enum EditorTheme: String, CaseIterable, Identifiable {
    case paper
    case snow
    case linen
    case ink
    case graphite
    case midnight

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: "Paper"
        case .snow: "Snow"
        case .linen: "Linen"
        case .ink: "Ink"
        case .graphite: "Graphite"
        case .midnight: "Midnight"
        }
    }

    var isDark: Bool {
        switch self {
        case .ink, .graphite, .midnight: true
        case .paper, .snow, .linen: false
        }
    }

    var palette: ThemePalette {
        switch self {
        case .paper:
            ThemePalette(background: .rgb(0.965, 0.953, 0.925), foreground: .rgb(0.13, 0.12, 0.10), secondary: .rgb(0.40, 0.38, 0.34), selection: .rgb(0.80, 0.77, 0.68))
        case .snow:
            ThemePalette(background: .white, foreground: .rgb(0.05, 0.05, 0.05), secondary: .rgb(0.34, 0.34, 0.34), selection: .rgb(0.72, 0.81, 0.96))
        case .linen:
            ThemePalette(background: .rgb(0.91, 0.88, 0.82), foreground: .rgb(0.22, 0.20, 0.17), secondary: .rgb(0.44, 0.41, 0.36), selection: .rgb(0.76, 0.70, 0.60))
        case .ink:
            ThemePalette(background: .rgb(0.055, 0.06, 0.065), foreground: .rgb(0.94, 0.94, 0.92), secondary: .rgb(0.62, 0.63, 0.61), selection: .rgb(0.24, 0.34, 0.46))
        case .graphite:
            ThemePalette(background: .rgb(0.13, 0.13, 0.12), foreground: .rgb(0.76, 0.75, 0.72), secondary: .rgb(0.52, 0.51, 0.48), selection: .rgb(0.31, 0.30, 0.27))
        case .midnight:
            ThemePalette(background: .rgb(0.06, 0.085, 0.11), foreground: .rgb(0.78, 0.83, 0.86), secondary: .rgb(0.48, 0.56, 0.61), selection: .rgb(0.17, 0.28, 0.34))
        }
    }
}

struct ThemePalette {
    let background: NSColor
    let foreground: NSColor
    let secondary: NSColor
    let selection: NSColor

}

private extension NSColor {
    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

enum FontChoice: String, CaseIterable, Identifiable {
    case newYork
    case iowan
    case charter
    case sfPro
    case avenirNext
    case helveticaNeue

    var id: String { rawValue }

    var name: String {
        switch self {
        case .newYork: "New York"
        case .iowan: "Iowan Old Style"
        case .charter: "Charter"
        case .sfPro: "SF Pro"
        case .avenirNext: "Avenir Next"
        case .helveticaNeue: "Helvetica Neue"
        }
    }

    var family: String { isSerif ? "Serif" : "Sans-serif" }

    var isSerif: Bool {
        switch self {
        case .newYork, .iowan, .charter: true
        case .sfPro, .avenirNext, .helveticaNeue: false
        }
    }

    func nsFont(size: CGFloat) -> NSFont {
        switch self {
        case .newYork:
            NSFont(name: "NewYork-Regular", size: size) ?? NSFont(name: "IowanOldStyle-Roman", size: size) ?? NSFont(name: "Times-Roman", size: size) ?? .systemFont(ofSize: size)
        case .iowan:
            NSFont(name: "IowanOldStyle-Roman", size: size) ?? NSFont(name: "Times-Roman", size: size) ?? .systemFont(ofSize: size)
        case .charter:
            NSFont(name: "Charter-Roman", size: size) ?? NSFont(name: "Times-Roman", size: size) ?? .systemFont(ofSize: size)
        case .sfPro:
            .systemFont(ofSize: size, weight: .regular)
        case .avenirNext:
            NSFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size, weight: .regular)
        case .helveticaNeue:
            NSFont(name: "HelveticaNeue", size: size) ?? .systemFont(ofSize: size, weight: .regular)
        }
    }
}

enum TypewriterSound: String, CaseIterable, Identifiable {
    case off
    case soft

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .soft: "Soft"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var theme: EditorTheme { didSet { store(theme.rawValue, for: "theme") } }
    @Published var font: FontChoice { didSet { store(font.rawValue, for: "font") } }
    @Published var typewriterSound: TypewriterSound { didSet { store(typewriterSound.rawValue, for: "sound") } }
    @Published var showsWordCount: Bool { didSet { store(showsWordCount, for: "showsWordCount") } }

    init(defaults: UserDefaults = .standard) {
        theme = EditorTheme(rawValue: defaults.string(forKey: "plaintext.theme") ?? "paper") ?? .paper
        font = FontChoice(rawValue: defaults.string(forKey: "plaintext.font") ?? "newYork") ?? .newYork
        typewriterSound = TypewriterSound(rawValue: defaults.string(forKey: "plaintext.sound") ?? "off") ?? .off
        showsWordCount = defaults.object(forKey: "plaintext.showsWordCount") as? Bool ?? false
    }

    private func store(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: "plaintext.\(key)")
    }

    private func store(_ value: Bool, for key: String) {
        UserDefaults.standard.set(value, forKey: "plaintext.\(key)")
    }
}

@MainActor
final class InterfaceState: ObservableObject {
    @Published var showingSettings = false
    @Published var showingFind = false
    @Published var showingHistory = false
    @Published var showingCommandPalette = false
    @Published var alertMessage: String?
}

struct HistorySnapshot: Identifiable, Hashable {
    let url: URL
    let date: Date

    var id: URL { url }
}
