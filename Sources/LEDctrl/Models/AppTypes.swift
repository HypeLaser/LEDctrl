import SigmaProtocol
import Foundation
import SwiftUI
import AppKit

enum SectionID: Hashable {
    case messages
    case headlines
    case progressBar
    case pixelGraphics
    case convert
    case playlists
    case plex
    case devices
    case systemSet
    case network
    case log
}

enum AppFont: String, CaseIterable, Identifiable {
    case normal5
    case normal7

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal5: return "Compact 5-high"
        case .normal7: return "Readable 5x7"
        }
    }

    var sigmaFont: SigmaFont {
        switch self {
        case .normal5: return .normal5
        case .normal7: return .normal7
        }
    }

    var maxCharactersPerLine: Int {
        sigmaFont.maxCharactersPerLine
    }

    var detail: String {
        switch self {
        case .normal5:
            return "shorter text, centered in 7 pixels"
        case .normal7:
            return "best readability"
        }
    }

    var pixelGlyphHeight: Int {
        switch self {
        case .normal5:
            return 5
        case .normal7:
            return 7
        }
    }

    var editorPointSize: CGFloat {
        switch self {
        case .normal5:
            return 20
        case .normal7:
            return 24
        }
    }

    var markupToken: String {
        switch self {
        case .normal5: return "font5"
        case .normal7: return "font7"
        }
    }
}

enum CanvasAlignment: String, CaseIterable, Identifiable, Sendable {
    case left
    case center
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var sigmaCode: UInt8 {
        switch self {
        case .center: return UInt8(ascii: "0")
        case .left: return UInt8(ascii: "1")
        case .right: return UInt8(ascii: "2")
        }
    }
}

enum AppColor: String, CaseIterable, Identifiable, Sendable {
    case red
    case green
    case orange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Red"
        case .green: return "Green"
        case .orange: return "Orange"
        }
    }

    var sigmaColor: SigmaColor {
        switch self {
        case .red: return .red
        case .green: return .green
        case .orange: return .orange
        }
    }

    var previewColor: Color {
        switch self {
        case .red: return Color(red: 1.0, green: 0.08, blue: 0.08)
        case .green: return Color(red: 0.12, green: 0.95, blue: 0.18)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.10)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: return NSColor(calibratedRed: 1.0, green: 0.08, blue: 0.08, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.12, green: 0.95, blue: 0.18, alpha: 1)
        case .orange: return NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
        }
    }

    var markupToken: String {
        switch self {
        case .red: return "red"
        case .green: return "green"
        case .orange: return "orange"
        }
    }
}

enum AppPalette: String, CaseIterable, Identifiable {
    case solid
    case horizontalBands
    case characterStripes
    case diagonalDown
    case diagonalUp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid: return "Solid"
        case .horizontalBands: return "Bands"
        case .characterStripes: return "By Character"
        case .diagonalDown: return "Diagonal Down"
        case .diagonalUp: return "Diagonal Up"
        }
    }

    func color(x: Int, y: Int, characterIndex: Int?, fallback: Color) -> Color {
        switch self {
        case .solid:
            return fallback
        case .characterStripes:
            return stripeColor(characterIndex ?? 0)
        case .horizontalBands:
            if y <= 1 { return .yellow }
            if y <= 3 { return .green }
            return .red
        case .diagonalDown:
            return stripeColor((x + y) % 3)
        case .diagonalUp:
            return stripeColor((x + (6 - y)) % 3)
        }
    }

    func sendColor(base: AppColor) -> SigmaColor {
        switch self {
        case .solid:
            return base.sigmaColor
        case .horizontalBands:
            return .mixedBands
        case .characterStripes:
            return .mixedCharacters
        case .diagonalDown:
            return .mixedDiagonalDown
        case .diagonalUp:
            return .mixedDiagonalUp
        }
    }

    private func stripeColor(_ index: Int) -> Color {
        switch index % 3 {
        case 0: return .red
        case 1: return .green
        default: return .yellow
        }
    }
}

enum MessageMode: String, CaseIterable, Identifiable, Sendable {
    case fitted
    case marquee

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fitted: return "Fitted"
        case .marquee: return "Marquee"
        }
    }
}

enum HeadlineMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case fitted
    case marquee

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .fitted: return "Fit"
        case .marquee: return "Scroll"
        }
    }
}

enum GraphicsBrush: String, CaseIterable, Identifiable, Sendable {
    case red
    case green
    case orange
    case erase

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Red"
        case .green: return "Green"
        case .orange: return "Orange"
        case .erase: return "Erase"
        }
    }

    var swatchColor: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .erase: return .black
        }
    }
}

enum ConvertSourceMode: String, CaseIterable, Identifiable, Sendable {
    case videoFile
    case pngSequenceFolder

    var id: String { rawValue }
}

enum SenderProfile: String, CaseIterable, Identifiable, Sendable {
    case stable
    case editorFont

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stable: return "Stable"
        case .editorFont: return "Editor Font"
        }
    }
}

enum ProgressSendEngine: String, CaseIterable, Identifiable, Sendable {
    case textFallback
    case backgroundReplay
    case bitmapTemplate
    case bitmapRaw
    case bitmapEditorProgram
    case bitmapEditorGeneric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .textFallback: return "Text (Stable)"
        case .backgroundReplay: return "Background Replay (Stable)"
        case .bitmapTemplate: return "Bitmap Template (Experimental)"
        case .bitmapRaw: return "Bitmap Raw (Experimental)"
        case .bitmapEditorProgram: return "Bitmap Editor Program (Experimental)"
        case .bitmapEditorGeneric: return "Bitmap Editor Generic (Experimental)"
        }
    }
}

struct SigmaEffect: Identifiable, Hashable {
    let id: Int
    let name: String

    static let all: [SigmaEffect] = [
        "Random", "Jump out", "Move left", "Move right", "Scroll left", "Scroll right",
        "Move up", "Move down", "Scroll to L/R", "Scroll up", "Scroll down",
        "Fold from L/R", "Fold from U/D", "Scroll to U/D", "Shuttle from L/R",
        "Shuttle from U/D", "Peel off L", "Peel off R", "Shutter from U/D",
        "Shutter from L/R", "Raindrops", "Random mosaic", "Twinkling stars",
        "Radar scan", "Fan out", "Fan in", "Spiral R", "Spiral L",
        "To four corners", "From four corners", "To four sides", "From four sides",
        "Scroll out from four blocks.", "Scroll in to four blocks.",
        "Move out from four blocks.", "Move in to four blocks.",
        "Scrl from U/left,square.", "Scrl from U/right,square.",
        "Scrl from L/left,square.", "Scrl from R/right,square.",
        "Scrl from U/left,slanting.", "Scrl from U/right,slanting.",
        "Scrl from L/left,slanting.", "Scrl from L/right,slanting.",
        "Move in from U/left corner.", "Move in from U/right corner.",
        "Move in from L/left corner.", "Move in from L/right corner.", "Growing up"
    ].enumerated().map { SigmaEffect(id: $0.offset, name: $0.element) }

    var sigmaCode: UInt8 {
        UInt8(0x2f + id)
    }

    static let jumpOutCode = UInt8(ascii: "0")
}

enum SigmaSpeed: Int, CaseIterable, Identifiable, Sendable {
    case veryFast
    case fast
    case mediumFast
    case medium
    case mediumSlow
    case slow
    case verySlow

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .veryFast: return "Very Fast"
        case .fast: return "Fast"
        case .mediumFast: return "Medium Fast"
        case .medium: return "Medium"
        case .mediumSlow: return "Medium Slow"
        case .slow: return "Slow"
        case .verySlow: return "Very Slow"
        }
    }

    var sigmaCode: UInt8 {
        UInt8(ascii: "0") + UInt8(rawValue)
    }

    var previewPixelsPerSecond: Double {
        switch self {
        case .veryFast: return 80
        case .fast: return 70
        case .mediumFast: return 60
        case .medium: return 53
        case .mediumSlow: return 48
        case .slow: return 44
        case .verySlow: return 40
        }
    }
}
