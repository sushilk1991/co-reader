import SwiftUI

/// Reading surface themes. The whole window takes its colours from the active theme so
/// the chrome never fights the page.
enum ReaderTheme: String, CaseIterable, Identifiable, Codable {
    case paper, sepia, dusk, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .dusk: "Dusk"
        case .night: "Night"
        }
    }

    var isDark: Bool { self == .dusk || self == .night }

    var palette: Palette {
        switch self {
        case .paper:
            Palette(page: 0xFBF8F1, surface: 0xF3EEE3, raised: 0xFFFDF8, ink: 0x1F1B16, secondary: 0x6B6257,
                    tertiary: 0xA39A8C, rule: 0xE2DACB, accent: 0xB3402A, selection: 0xF2D9A6)
        case .sepia:
            Palette(page: 0xF4E9D3, surface: 0xEADDC2, raised: 0xFAF1DE, ink: 0x3A2D1E, secondary: 0x7A6850,
                    tertiary: 0xA8967B, rule: 0xD9C8A6, accent: 0x9A4A1F, selection: 0xE6C98C)
        case .dusk:
            Palette(page: 0x26231F, surface: 0x1E1C19, raised: 0x302C27, ink: 0xE4DCCD, secondary: 0xA39A8B,
                    tertiary: 0x736B5F, rule: 0x3A352F, accent: 0xE08A5B, selection: 0x5A4A2E)
        case .night:
            Palette(page: 0x121110, surface: 0x0B0A09, raised: 0x1B1917, ink: 0xC9C2B4, secondary: 0x8B8377,
                    tertiary: 0x5C564D, rule: 0x26231F, accent: 0xD9805A, selection: 0x4A3D26)
        }
    }
}

struct Palette {
    let page: Color
    let surface: Color
    let raised: Color
    let ink: Color
    let secondary: Color
    let tertiary: Color
    let rule: Color
    let accent: Color
    let selection: Color
    let hex: [String: String]

    init(page: UInt32, surface: UInt32, raised: UInt32, ink: UInt32, secondary: UInt32,
         tertiary: UInt32, rule: UInt32, accent: UInt32, selection: UInt32) {
        self.page = Color(hex: page)
        self.surface = Color(hex: surface)
        self.raised = Color(hex: raised)
        self.ink = Color(hex: ink)
        self.secondary = Color(hex: secondary)
        self.tertiary = Color(hex: tertiary)
        self.rule = Color(hex: rule)
        self.accent = Color(hex: accent)
        self.selection = Color(hex: selection)
        func css(_ v: UInt32) -> String { String(format: "#%06X", v) }
        hex = ["page": css(page), "ink": css(ink), "accent": css(accent), "selection": css(selection), "rule": css(rule)]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ReaderTheme.paper.palette
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Typography: a serif for anything that is a title or a quote, the system face for controls.
enum Typo {
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let f = Font.custom("Iowan Old Style", size: size)
        return italic ? f.italic() : f
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Small tracked capitals for section labels.
    static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .semibold)
    }
}

extension View {
    /// Section label: small, tracked, uppercase.
    func labelStyle(_ palette: Palette) -> some View {
        self.font(Typo.label()).tracking(1.1).textCase(.uppercase).foregroundStyle(palette.tertiary)
    }
}

extension HighlightTint {
    var color: Color {
        switch self {
        case .yellow: Color(hex: 0xF5C518)
        case .green: Color(hex: 0x6FBF73)
        case .blue: Color(hex: 0x5AA9F0)
        case .pink: Color(hex: 0xF07AA8)
        case .purple: Color(hex: 0xA784F0)
        }
    }
}
