import Foundation
import SwiftUI

struct SerialPort: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let hint: String
}

struct ProbeResult: Identifiable {
    let id = UUID()
    let target: String
    let status: String
    let response: String
}

struct PlaylistItem: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let inMode: SigmaEffect
    let outMode: SigmaEffect
    let speed: SigmaSpeed
    let pauseSeconds: Int
}

struct CanvasStyleRun: Identifiable, Hashable, Sendable {
    let id = UUID()
    var location: Int
    var length: Int
    var token: String

    var range: NSRange {
        NSRange(location: location, length: length)
    }
}

struct MessageRow: Identifiable, Hashable {
    let id: UUID
    var order: Int
    var text: String
    var mode: MessageMode
    var font: AppFont
    var color: AppColor
    var palette: AppPalette
    var inMode: SigmaEffect
    var outMode: SigmaEffect
    var speed: SigmaSpeed
    var pauseSeconds: Int
    var useCustomEffects: Bool

    init(
        id: UUID = UUID(),
        order: Int,
        text: String,
        mode: MessageMode,
        font: AppFont,
        color: AppColor,
        palette: AppPalette,
        inMode: SigmaEffect,
        outMode: SigmaEffect,
        speed: SigmaSpeed,
        pauseSeconds: Int,
        useCustomEffects: Bool = false
    ) {
        self.id = id
        self.order = order
        self.text = text
        self.mode = mode
        self.font = font
        self.color = color
        self.palette = palette
        self.inMode = inMode
        self.outMode = outMode
        self.speed = speed
        self.pauseSeconds = pauseSeconds
        self.useCustomEffects = useCustomEffects
    }
}

/// Per-row Effects-mode override. `enabled = false` means the row uses the
/// global In/Out from the canvas-level pickers. When `enabled = true`,
/// `inMode` / `outMode` are emitted as inline effect-change bytes before
/// that row in the wire output.
struct RowEffectOverride: Identifiable, Hashable {
    let id: UUID
    var enabled: Bool
    var inMode: SigmaEffect
    var outMode: SigmaEffect

    init(
        id: UUID = UUID(),
        enabled: Bool = false,
        inMode: SigmaEffect = SigmaEffect.all[1],
        outMode: SigmaEffect = SigmaEffect.all[1]
    ) {
        self.id = id
        self.enabled = enabled
        self.inMode = inMode
        self.outMode = outMode
    }
}

enum ProgressPixel: Equatable, Sendable {
    case off
    case red
    case green
    case orange

    init(color: AppColor) {
        switch color {
        case .red: self = .red
        case .green: self = .green
        case .orange: self = .orange
        }
    }

    var rgb565: UInt16 {
        switch self {
        case .off: return 0x0000
        case .red: return 0xf800
        case .green: return 0x07e0
        case .orange: return 0xffe0
        }
    }

    var rgba: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        switch self {
        case .off:
            return (0, 0, 0, 255)
        case .red:
            return (255, 0, 0, 255)
        case .green:
            return (0, 255, 0, 255)
        case .orange:
            return (255, 165, 0, 255)
        }
    }
}

struct CanvasLinePayload: Sendable {
    let rowIndex: Int
    let rawText: String
    let serializedText: String
    let styleRuns: [CanvasStyleRun]
    let alignment: CanvasAlignment
}

struct ProgressFrame {
    let pixels: [ProgressPixel]
    let renderedPixels: PixelFontRenderer.RenderedPixels
}
