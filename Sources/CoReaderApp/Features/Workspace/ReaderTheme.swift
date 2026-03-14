import AppKit
import SwiftUI

enum ReaderTheme {

    // MARK: - Surfaces

    static let backdrop = adaptive(
        light: (0.91, 0.87, 0.81),
        dark: (0.10, 0.09, 0.08)
    )
    static let canvas = adaptive(
        light: (0.96, 0.94, 0.90),
        dark: (0.13, 0.12, 0.11)
    )
    static let paper = adaptive(
        light: (0.99, 0.98, 0.96),
        dark: (0.17, 0.16, 0.14)
    )
    static let panel = adaptive(
        light: (0.93, 0.90, 0.85),
        dark: (0.12, 0.11, 0.10)
    )
    static let panelRaised = adaptive(
        light: (0.96, 0.94, 0.90),
        dark: (0.15, 0.14, 0.13)
    )
    static let chrome = panel
    static let chromeStrong = adaptive(
        light: (0.79, 0.72, 0.63),
        dark: (0.32, 0.29, 0.26)
    )

    // MARK: - Lines & Borders

    static let line = adaptive(
        light: (0.84, 0.77, 0.69),
        dark: (0.26, 0.23, 0.20)
    )
    static let lineSoft = adaptive(
        light: (0.89, 0.84, 0.77),
        dark: (0.21, 0.19, 0.17)
    )

    // MARK: - Text

    static let ink = adaptive(
        light: (0.18, 0.15, 0.12),
        dark: (0.93, 0.91, 0.88)
    )
    static let slate = adaptive(
        light: (0.41, 0.36, 0.31),
        dark: (0.65, 0.60, 0.55)
    )
    static let smoke = adaptive(
        light: (0.56, 0.49, 0.42),
        dark: (0.50, 0.46, 0.41)
    )

    // MARK: - Accents

    static let teal = adaptive(
        light: (0.11, 0.46, 0.43),
        dark: (0.22, 0.65, 0.60)
    )
    static let tealSoft = adaptive(
        light: (0.86, 0.93, 0.91),
        dark: (0.10, 0.18, 0.17)
    )
    static let brass = adaptive(
        light: (0.67, 0.52, 0.24),
        dark: (0.80, 0.65, 0.32)
    )
    static let brassSoft = adaptive(
        light: (0.95, 0.91, 0.81),
        dark: (0.20, 0.17, 0.10)
    )
    static let rose = adaptive(
        light: (0.63, 0.34, 0.28),
        dark: (0.80, 0.45, 0.38)
    )
    static let roseSoft = adaptive(
        light: (0.96, 0.89, 0.86),
        dark: (0.22, 0.12, 0.10)
    )

    // MARK: - Effects

    static let shadow = adaptiveAlpha(
        light: (0.19, 0.15, 0.11, 0.10),
        dark: (0.0, 0.0, 0.0, 0.40)
    )
    static let workspaceGlow = adaptive(
        light: (1.0, 1.0, 1.0),
        dark: (0.20, 0.18, 0.15)
    )

    // MARK: - Gradients

    static let workspaceGradient = LinearGradient(
        colors: [
            adaptive(light: (0.97, 0.95, 0.91), dark: (0.11, 0.10, 0.09)),
            adaptive(light: (0.93, 0.89, 0.82), dark: (0.08, 0.07, 0.06))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelGradient = LinearGradient(
        colors: [panelRaised, panel],
        startPoint: .top,
        endPoint: .bottom
    )

    static let toolbarGradient = LinearGradient(
        colors: [panelRaised.opacity(0.98), panel.opacity(0.96)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let paperGradient = LinearGradient(
        colors: [paper, canvas.opacity(0.88)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Helpers

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }))
    }

    private static func adaptiveAlpha(
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b, a) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }))
    }
}
