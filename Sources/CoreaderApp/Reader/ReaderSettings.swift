import CoreaderKit
import Foundation

typealias HighlightTint = HighlightColor

enum ReadingFont: String, CaseIterable, Identifiable, Codable {
    case publisher, iowan, charter, newYork, palatino, baskerville, georgia, sans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publisher: "Original"
        case .iowan: "Iowan"
        case .charter: "Charter"
        case .newYork: "New York"
        case .palatino: "Palatino"
        case .baskerville: "Baskerville"
        case .georgia: "Georgia"
        case .sans: "San Francisco"
        }
    }

    var css: String {
        switch self {
        case .publisher, .iowan: "'Iowan Old Style', 'Palatino', Georgia, serif"
        case .charter: "Charter, 'Iowan Old Style', Georgia, serif"
        case .newYork: "ui-serif, 'New York', 'Iowan Old Style', serif"
        case .palatino: "Palatino, 'Iowan Old Style', serif"
        case .baskerville: "Baskerville, 'Iowan Old Style', serif"
        case .georgia: "Georgia, serif"
        case .sans: "-apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        }
    }
}

enum PageTurn: String, CaseIterable, Identifiable, Codable {
    case turn, slide, none, scroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turn: "Page turn"
        case .slide: "Slide"
        case .none: "Instant"
        case .scroll: "Scroll"
        }
    }
}

/// Everything the reader lets you tune. Persisted in UserDefaults as one JSON value.
struct ReaderSettings: Codable, Equatable {
    var theme: ReaderTheme = .paper
    var followsSystemAppearance = true
    var font: ReadingFont = .publisher
    var fontSize: Double = 19
    var lineHeight: Double = 1.6
    var justify = true
    var twoPages = true
    var pageTurn: PageTurn = .turn
    var maxLineWidth: Double = 640

    static let key = "reader.settings.v1"

    static func load() -> ReaderSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(ReaderSettings.self, from: data) else { return ReaderSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// The object `bridge.js` `applySettings` expects.
    func webPayload(theme: ReaderTheme) -> [String: Any] {
        let p = theme.palette.hex
        return [
            "dark": theme.isDark,
            "ink": p["ink"]!, "accent": p["accent"]!, "selection": p["selection"]!, "rule": p["rule"]!,
            "fontFamily": font.css,
            "overrideFonts": font != .publisher,
            "fontSize": fontSize,
            "lineHeight": lineHeight,
            "justify": justify,
            "flow": pageTurn == .scroll ? "scrolled" : "paginated",
            "animated": pageTurn == .slide,
            "columns": twoPages ? 2 : 1,
            "maxInlineSize": maxLineWidth,
            "gap": 7,
            "margin": 64,
        ]
    }
}

extension Book {
    /// Author line that stays short on the shelf: "A. Author", "A and B", or "A et al.".
    var shortAuthors: String {
        switch authors.count {
        case 0: ""
        case 1: authors[0]
        case 2: authors.joined(separator: " and ")
        default: "\(authors[0]) et al."
        }
    }
}

extension Double {
    /// Whole percent of a 0...1 value, safe for NaN and infinity (which `Int(_:)` traps on).
    var percent: Int { isFinite ? Int((Swift.min(Swift.max(self, 0), 1) * 100).rounded()) : 0 }
    /// Whole minutes of a number of seconds, safe for NaN and infinity.
    var minutes: Int { isFinite ? Int(Swift.max(self, 0) / 60) : 0 }
}
