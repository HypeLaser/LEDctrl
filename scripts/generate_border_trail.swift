import AppKit
import Foundation

enum Pixel: UInt8 {
    case off = 0
    case red = 1
    case orange = 2
    case green = 3
}

struct RGB {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

let ledWidth = 80
let ledHeight = 7
let scale = 2
let outWidth = ledWidth * scale
let outHeight = ledHeight * scale

let outputDir: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }
    return URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Desktop", isDirectory: true)
        .appendingPathComponent("Test", isDirectory: true)
}()

func color(for pixel: Pixel) -> RGB {
    switch pixel {
    case .off:
        return RGB(r: 0, g: 0, b: 0)
    case .red:
        return RGB(r: 255, g: 0, b: 0)
    case .orange:
        return RGB(r: 255, g: 165, b: 0)
    case .green:
        return RGB(r: 0, g: 255, b: 0)
    }
}

func indexFor(x: Int, y: Int) -> Int {
    // User mapping: row-major, 1...560, so zero-based index is y*80 + x
    return y * ledWidth + x
}

func borderPath() -> [(x: Int, y: Int)] {
    var path: [(x: Int, y: Int)] = []

    // Top row: left -> right
    for x in 0..<ledWidth {
        path.append((x, 0))
    }
    // Right column: top -> bottom (excluding top-right)
    for y in 1..<ledHeight {
        path.append((ledWidth - 1, y))
    }
    // Bottom row: right -> left (excluding bottom-right)
    if ledHeight > 1 {
        for x in stride(from: ledWidth - 2, through: 0, by: -1) {
            path.append((x, ledHeight - 1))
        }
    }
    // Left column: bottom -> top (excluding bottom-left and top-left)
    if ledWidth > 1 && ledHeight > 2 {
        for y in stride(from: ledHeight - 2, through: 1, by: -1) {
            path.append((0, y))
        }
    }

    return path
}

func makePNG(pixels: [Pixel]) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: outWidth,
        pixelsHigh: outHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: outWidth * 4,
        bitsPerPixel: 32
    ), let dataPtr = rep.bitmapData else {
        throw NSError(domain: "BorderTrail", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate bitmap"])
    }

    for y in 0..<ledHeight {
        for x in 0..<ledWidth {
            let px = pixels[indexFor(x: x, y: y)]
            let c = color(for: px)
            let yBase = y * scale
            for dy in 0..<scale {
                for dx in 0..<scale {
                    let dstX = x * scale + dx
                    let dstY = yBase + dy
                    let offset = (dstY * outWidth + dstX) * 4
                    dataPtr[offset + 0] = c.r
                    dataPtr[offset + 1] = c.g
                    dataPtr[offset + 2] = c.b
                    dataPtr[offset + 3] = 255
                }
            }
        }
    }

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BorderTrail", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    return png
}

let path = borderPath()
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// We generate one frame per path step, with a persistent cool trail:
// head = red, previous = orange, and all earlier visited border pixels stay green.
// Then we add two cool-down frames so the border settles fully green.
let generatedFrameCount = path.count + 2
for frame in 0..<generatedFrameCount {
    var pixels = Array(repeating: Pixel.off, count: ledWidth * ledHeight)

    // Persist visited pixels as green.
    let stableThrough = min(frame - 2, path.count - 1)
    if stableThrough >= 0 {
        for i in 0...stableThrough {
            let p = path[i]
            pixels[indexFor(x: p.x, y: p.y)] = .green
        }
    }

    // Warm pixel (previous step).
    if frame - 1 >= 0 && frame - 1 < path.count {
        let warm = path[frame - 1]
        pixels[indexFor(x: warm.x, y: warm.y)] = .orange
    }

    // Head pixel (current step).
    if frame < path.count {
        let head = path[frame]
        pixels[indexFor(x: head.x, y: head.y)] = .red
    }

    let png = try makePNG(pixels: pixels)
    let name = String(format: "frame-%03d.png", frame + 1)
    let url = outputDir.appendingPathComponent(name)
    try png.write(to: url, options: .atomic)
}

let summary = """
Generated \(generatedFrameCount) frames
Resolution: \(outWidth)x\(outHeight)
LED matrix: \(ledWidth)x\(ledHeight)
Output: \(outputDir.path)
"""
print(summary)
