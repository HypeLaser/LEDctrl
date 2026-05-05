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
        .appendingPathComponent("Test3", isDirectory: true)
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
    return y * ledWidth + x
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
        throw NSError(domain: "SplitSeal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate bitmap"])
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
        throw NSError(domain: "SplitSeal", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    return png
}

func makeTopHeadPath() -> [(Int, Int)] {
    var p: [(Int, Int)] = []
    // Start at middle of right column: row 4 (1-based) => y=3
    p.append((79, 3))
    // Up to top-right.
    p.append((79, 2))
    p.append((79, 1))
    p.append((79, 0))
    // Across top, right -> left.
    for x in stride(from: 78, through: 0, by: -1) {
        p.append((x, 0))
    }
    // Down left edge to middle.
    p.append((0, 1))
    p.append((0, 2))
    p.append((0, 3))
    return p
}

func makeBottomHeadPath() -> [(Int, Int)] {
    var p: [(Int, Int)] = []
    // Start at middle of right column: row 4 (1-based) => y=3
    p.append((79, 3))
    // Down to bottom-right.
    p.append((79, 4))
    p.append((79, 5))
    p.append((79, 6))
    // Across bottom, right -> left.
    for x in stride(from: 78, through: 0, by: -1) {
        p.append((x, 6))
    }
    // Up left edge to middle.
    p.append((0, 5))
    p.append((0, 4))
    p.append((0, 3))
    return p
}

let topPath = makeTopHeadPath()
let bottomPath = makeBottomHeadPath()
let frameSteps = min(topPath.count, bottomPath.count)
let generatedFrameCount = frameSteps + 2 // cool-down frames

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for frame in 0..<generatedFrameCount {
    var pixels = Array(repeating: Pixel.off, count: ledWidth * ledHeight)

    // Persist old visited points as green.
    let stableThrough = min(frame - 2, frameSteps - 1)
    if stableThrough >= 0 {
        for i in 0...stableThrough {
            let t = topPath[i]
            let b = bottomPath[i]
            pixels[indexFor(x: t.0, y: t.1)] = .green
            pixels[indexFor(x: b.0, y: b.1)] = .green
        }
    }

    // Previous step as orange.
    if frame - 1 >= 0 && frame - 1 < frameSteps {
        let t = topPath[frame - 1]
        let b = bottomPath[frame - 1]
        pixels[indexFor(x: t.0, y: t.1)] = .orange
        pixels[indexFor(x: b.0, y: b.1)] = .orange
    }

    // Current step as red.
    if frame < frameSteps {
        let t = topPath[frame]
        let b = bottomPath[frame]
        pixels[indexFor(x: t.0, y: t.1)] = .red
        pixels[indexFor(x: b.0, y: b.1)] = .red
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
