import AppKit
import Foundation
import SigmaProtocol

enum Pixel {
    case off
    case red
    case green
    case orange

    var rgb565: UInt16 {
        switch self {
        case .off: return 0x0000
        case .red: return 0xf800
        case .green: return 0x07e0
        case .orange: return 0xffe0
        }
    }
}

struct Config {
    var host: String
    var framesDir: String
    var holdSeconds: Int = 1
    var limit: Int?
}

func usage() {
    print("Usage: LEDPngSequenceSend <host> <framesDir> [--hold <seconds>] [--limit <count>]")
}

func parseConfig() -> Config? {
    let args = CommandLine.arguments.filter { $0 != "--" }
    guard args.count >= 3 else { return nil }

    var cfg = Config(host: args[1], framesDir: args[2])
    var idx = 3
    while idx < args.count {
        switch args[idx] {
        case "--hold" where idx + 1 < args.count:
            cfg.holdSeconds = max(1, min(255, Int(args[idx + 1]) ?? 1))
            idx += 2
        case "--limit" where idx + 1 < args.count:
            cfg.limit = max(1, Int(args[idx + 1]) ?? 1)
            idx += 2
        default:
            print("Unknown argument: \(args[idx])")
            return nil
        }
    }
    return cfg
}

func sortedFrameURLs(in directory: String) throws -> [URL] {
    let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
    let urls = try FileManager.default.contentsOfDirectory(
        at: dirURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    return urls
        .filter { $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix("frame-") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func bitmapRep(for url: URL) throws -> NSBitmapImageRep {
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        throw NSError(domain: "LEDPngSequenceSend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not decode image \(url.path)"])
    }
    return rep
}

func nearestPixel(_ rep: NSBitmapImageRep, x: Int, y: Int) -> NSColor {
    let sx = min(rep.pixelsWide - 1, max(0, Int((Double(x) + 0.5) * Double(rep.pixelsWide) / 80.0)))
    let sy = min(rep.pixelsHigh - 1, max(0, Int((Double(y) + 0.5) * Double(rep.pixelsHigh) / 7.0)))
    return rep.colorAt(x: sx, y: sy) ?? .black
}

func classify(_ color: NSColor) -> Pixel {
    let c = color.usingColorSpace(.deviceRGB) ?? color
    let r = Int(round(c.redComponent * 255))
    let g = Int(round(c.greenComponent * 255))
    let b = Int(round(c.blueComponent * 255))

    if r < 20 && g < 20 && b < 20 { return .off }
    if r > 200 && g < 90 { return .red }
    if r > 180 && g > 90 { return .orange }
    if g > 150 && r < 120 { return .green }
    return .off
}

func extractPixels(from rep: NSBitmapImageRep) -> [Pixel] {
    var pixels: [Pixel] = []
    pixels.reserveCapacity(80 * 7)
    for y in 0..<7 {
        for x in 0..<80 {
            let color = nearestPixel(rep, x: x, y: y)
            pixels.append(classify(color))
        }
    }
    return pixels
}

func makeRGB565BMP(width: Int, height: Int, pixels: [Pixel]) -> Data {
    let rowBytes = width * 2
    let rowStride = ((rowBytes + 3) / 4) * 4
    let imageSize = rowStride * height
    let pixelOffset = 14 + 40 + 12
    let fileSize = pixelOffset + imageSize

    var data = Data()
    data.append(contentsOf: [0x42, 0x4d]) // BM
    data.appendLE32(UInt32(fileSize))
    data.appendLE16(0)
    data.appendLE16(0)
    data.appendLE32(UInt32(pixelOffset))
    data.appendLE32(40) // DIB
    data.appendLE32(UInt32(width))
    data.appendLE32(UInt32(height))
    data.appendLE16(1)
    data.appendLE16(16)
    data.appendLE32(3) // BI_BITFIELDS
    data.appendLE32(UInt32(imageSize))
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0x0000f800)
    data.appendLE32(0x000007e0)
    data.appendLE32(0x0000001f)

    let padding = rowStride - rowBytes
    for y in stride(from: height - 1, through: 0, by: -1) {
        for x in 0..<width {
            data.appendLE16(pixels[y * width + x].rgb565)
        }
        if padding > 0 {
            data.append(contentsOf: repeatElement(UInt8(0), count: padding))
        }
    }
    return data
}

func replaceBmp(in template: Data, with bmp: Data) -> Data? {
    guard template.count >= bmp.count else { return nil }
    var offset = 0
    while offset + bmp.count <= template.count {
        guard let marker = template[offset...].firstRange(of: Data([0x42, 0x4d])) else { break }
        let bmOffset = marker.lowerBound
        if bmOffset + bmp.count <= template.count {
            var candidate = template
            candidate.replaceSubrange(bmOffset..<(bmOffset + bmp.count), with: bmp)
            return candidate
        }
        offset = bmOffset + 2
    }
    return nil
}

func loadTemplateNmg() throws -> Data {
    let candidates = [
        Paths.projectRoot.appendingPathComponent("analysis/templates/editor-picture-template.Nmg").path(),
        Paths.demoDirectory.appendingPathComponent("chevron-80x7-generated.nmg").path(),
        Paths.demoDirectory.appendingPathComponent("chevron-80x7-showbmp-24.nmg").path()
    ]
    for path in candidates {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty {
            return data
        }
    }
    throw NSError(domain: "LEDPngSequenceSend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not load picture NMG template"])
}

func makeEntry(filename: String, pngURL: URL, template: Data) throws -> SigmaBinaryProgramEntry {
    let rep = try bitmapRep(for: pngURL)
    let pixels = extractPixels(from: rep)
    let bmp = makeRGB565BMP(width: 80, height: 7, pixels: pixels)
    let nmg = replaceBmp(in: template, with: bmp) ?? template
    return SigmaBinaryProgramEntry(
        filename: filename,
        content: nmg,
        fileType: .text,
        payloadLengthOverride: nmg.count
    )
}

do {
    guard let cfg = parseConfig() else {
        usage()
        exit(2)
    }

    var frameURLs = try sortedFrameURLs(in: cfg.framesDir)
    if let limit = cfg.limit {
        frameURLs = Array(frameURLs.prefix(limit))
    }
    guard !frameURLs.isEmpty else {
        throw NSError(domain: "LEDPngSequenceSend", code: 3, userInfo: [NSLocalizedDescriptionKey: "No frame-*.png files found in \(cfg.framesDir)"])
    }

    let template = try loadTemplateNmg()
    var entries: [SigmaBinaryProgramEntry] = []
    entries.reserveCapacity(frameURLs.count)
    for (index, url) in frameURLs.enumerated() {
        let filename = String(format: "PRG%03d.Nmg", index + 1)
        entries.append(try makeEntry(filename: filename, pngURL: url, template: template))
    }

    var client = SigmaClient(host: cfg.host)
    let steps = try client.sendEditorProgramEntries(entries, sequenceTimingCode: UInt8(cfg.holdSeconds))

    print("Prepared \(entries.count) frame entries from \(cfg.framesDir)")
    print("Hold per step: \(cfg.holdSeconds)s")
    for step in steps {
        print(step)
    }
} catch {
    print("error: \(error)")
    exit(1)
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
