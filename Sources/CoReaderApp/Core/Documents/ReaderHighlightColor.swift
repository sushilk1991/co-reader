import AppKit
import SwiftUI

enum ReaderHighlightColor: String, CaseIterable, Codable, Equatable, Sendable {
    case yellow
    case mint
    case sky
    case rose

    var label: String {
        switch self {
        case .yellow:
            "Yellow"
        case .mint:
            "Mint"
        case .sky:
            "Sky"
        case .rose:
            "Rose"
        }
    }

    var annotationColor: NSColor {
        switch self {
        case .yellow:
            NSColor(calibratedRed: 0.99, green: 0.90, blue: 0.20, alpha: 0.42)
        case .mint:
            NSColor(calibratedRed: 0.39, green: 0.84, blue: 0.71, alpha: 0.34)
        case .sky:
            NSColor(calibratedRed: 0.42, green: 0.69, blue: 0.96, alpha: 0.32)
        case .rose:
            NSColor(calibratedRed: 0.92, green: 0.58, blue: 0.63, alpha: 0.30)
        }
    }

    var swatchColor: Color {
        Color(nsColor: annotationColor)
    }

    var pillColor: Color {
        switch self {
        case .yellow:
            ReaderTheme.brassSoft
        case .mint:
            ReaderTheme.tealSoft
        case .sky:
            Color(.sRGB, red: 0.87, green: 0.92, blue: 0.98, opacity: 1)
        case .rose:
            ReaderTheme.roseSoft
        }
    }
}
