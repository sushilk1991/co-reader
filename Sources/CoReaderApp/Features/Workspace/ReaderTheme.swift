import SwiftUI

enum ReaderTheme {
    static let backdrop = Color(.sRGB, red: 0.91, green: 0.87, blue: 0.81, opacity: 1)
    static let canvas = Color(.sRGB, red: 0.96, green: 0.94, blue: 0.90, opacity: 1)
    static let paper = Color(.sRGB, red: 0.99, green: 0.98, blue: 0.96, opacity: 1)
    static let panel = Color(.sRGB, red: 0.93, green: 0.90, blue: 0.85, opacity: 1)
    static let panelRaised = Color(.sRGB, red: 0.96, green: 0.94, blue: 0.90, opacity: 1)
    static let chrome = panel
    static let chromeStrong = Color(.sRGB, red: 0.79, green: 0.72, blue: 0.63, opacity: 1)
    static let line = Color(.sRGB, red: 0.84, green: 0.77, blue: 0.69, opacity: 1)
    static let lineSoft = Color(.sRGB, red: 0.89, green: 0.84, blue: 0.77, opacity: 1)
    static let ink = Color(.sRGB, red: 0.18, green: 0.15, blue: 0.12, opacity: 1)
    static let slate = Color(.sRGB, red: 0.41, green: 0.36, blue: 0.31, opacity: 1)
    static let smoke = Color(.sRGB, red: 0.56, green: 0.49, blue: 0.42, opacity: 1)
    static let teal = Color(.sRGB, red: 0.11, green: 0.46, blue: 0.43, opacity: 1)
    static let tealSoft = Color(.sRGB, red: 0.86, green: 0.93, blue: 0.91, opacity: 1)
    static let brass = Color(.sRGB, red: 0.67, green: 0.52, blue: 0.24, opacity: 1)
    static let brassSoft = Color(.sRGB, red: 0.95, green: 0.91, blue: 0.81, opacity: 1)
    static let rose = Color(.sRGB, red: 0.63, green: 0.34, blue: 0.28, opacity: 1)
    static let roseSoft = Color(.sRGB, red: 0.96, green: 0.89, blue: 0.86, opacity: 1)
    static let shadow = Color(.sRGB, red: 0.19, green: 0.15, blue: 0.11, opacity: 0.10)

    static let workspaceGradient = LinearGradient(
        colors: [
            Color(.sRGB, red: 0.97, green: 0.95, blue: 0.91, opacity: 1),
            Color(.sRGB, red: 0.93, green: 0.89, blue: 0.82, opacity: 1)
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
}
