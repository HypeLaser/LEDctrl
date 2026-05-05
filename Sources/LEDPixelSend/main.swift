import Foundation
import SigmaProtocol

let args = CommandLine.arguments.filter { $0 != "--" }

guard args.count >= 3 else {
    print("Usage: LEDPixelSend <host> <80x7-map.txt> [--depth 16|24|32] [--save output.nmg]")
    exit(2)
}

let host = args[1]
let mapPath = args[2]
var savePath: String?
var bitDepth = 16
var idx = 3

while idx < args.count {
    switch args[idx] {
    case "--depth" where idx + 1 < args.count:
        bitDepth = Int(args[idx + 1]) ?? bitDepth
        idx += 2
    case "--save" where idx + 1 < args.count:
        savePath = args[idx + 1]
        idx += 2
    default:
        idx += 1
    }
}

do {
    let map = try PixelMap(path: mapPath)
    let bmp = try makeBmp(map: map, bitDepth: bitDepth)
    let nmg = makeBmpNmg(bmp: bmp)

    if let savePath {
        try nmg.write(to: URL(fileURLWithPath: savePath))
    }

    var client = SigmaClient(host: host)
    let steps = try client.sendNmg(nmg, filename: "temp.Nmg", fileType: .text)
    for step in steps {
        print(step)
    }
} catch {
    print("error: \(error)")
    exit(1)
}

private struct PixelMap {
    let width: Int
    let height: Int
    let pixels: [Pixel]

    init(path: String) throws {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let rows = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let first = rows.first, !first.isEmpty else {
            throw PixelError.emptyMap
        }
        let width = first.count
        guard rows.allSatisfy({ $0.count == width }) else {
            throw PixelError.raggedMap
        }

        self.width = width
        self.height = rows.count
        self.pixels = rows.flatMap { row in
            row.map { Pixel(character: $0) }
        }
    }

    func pixel(x: Int, y: Int) -> Pixel {
        pixels[y * width + x]
    }
}

private enum Pixel {
    case off
    case red
    case green
    case orange

    init(character: Character) {
        switch character.uppercased() {
        case "R": self = .red
        case "G": self = .green
        case "O", "Y", "A": self = .orange
        default: self = .off
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

    var bgr: [UInt8] {
        switch self {
        case .off: return [0, 0, 0]
        case .red: return [0, 0, 255]
        case .green: return [0, 255, 0]
        case .orange: return [0, 160, 255]
        }
    }
}

private enum PixelError: Error, CustomStringConvertible {
    case emptyMap
    case raggedMap
    case unsupportedDepth(Int)

    var description: String {
        switch self {
        case .emptyMap: return "pixel map is empty"
        case .raggedMap: return "pixel map rows are not all the same width"
        case .unsupportedDepth(let depth): return "unsupported BMP depth \(depth); use 16, 24, or 32"
        }
    }
}

private func makeBmpNmg(bmp: Data) -> Data {
    if let template = loadLightPictureTemplateNmg(),
       let replaced = replaceBmp(inTemplateNmg: template, with: bmp) {
        return replaced
    }
    var nmg = Data([
        0x01, 0x5a, 0x30, 0x30, 0x02, 0x41, 0x0a, 0x49,
        0x31, 0x0a, 0x4f, 0x31, 0x0e, 0x32, 0x30, 0x30,
        0x30, 0x32, 0x14, 0x40, 0x30, 0x04, 0x52, 0x43,
        0x01, 0x00, 0x01, 0x30
    ])
    nmg.appendLE32(UInt32(bmp.count))
    nmg.appendLE32(0x28)
    nmg.append(contentsOf: repeatElement(UInt8(0), count: max(0, 63 - nmg.count)))
    nmg.append(bmp)
    return nmg
}

private func loadLightPictureTemplateNmg() -> Data? {
    let candidates = [
        Paths.demoDirectory.appendingPathComponent("chevron-80x7-generated.nmg").path(),
        Paths.demoDirectory.appendingPathComponent("chevron-80x7-showbmp-24.nmg").path()
    ]
    for path in candidates {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return data
        }
    }
    return nil
}

private func replaceBmp(inTemplateNmg template: Data, with bmp: Data) -> Data? {
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

private func makeBmp(map: PixelMap, bitDepth: Int) throws -> Data {
    switch bitDepth {
    case 16:
        return makeRgb565Bmp(map: map)
    case 24, 32:
        return makeRgbBmp(map: map, bitDepth: bitDepth)
    default:
        throw PixelError.unsupportedDepth(bitDepth)
    }
}

private func makeRgb565Bmp(map: PixelMap) -> Data {
    let bytesPerPixel = 2
    let rowBytes = map.width * bytesPerPixel
    let rowStride = ((rowBytes + 3) / 4) * 4
    let imageSize = rowStride * map.height
    let pixelOffset = 14 + 40 + 12
    let fileSize = pixelOffset + imageSize

    var data = Data()
    data.append(contentsOf: [0x42, 0x4d])
    data.appendLE32(UInt32(fileSize))
    data.appendLE16(0)
    data.appendLE16(0)
    data.appendLE32(UInt32(pixelOffset))
    data.appendLE32(40)
    data.appendLE32(UInt32(map.width))
    data.appendLE32(UInt32(map.height))
    data.appendLE16(1)
    data.appendLE16(16)
    data.appendLE32(3)
    data.appendLE32(UInt32(imageSize))
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0x0000f800)
    data.appendLE32(0x000007e0)
    data.appendLE32(0x0000001f)

    let padding = rowStride - rowBytes
    for y in stride(from: map.height - 1, through: 0, by: -1) {
        for x in 0..<map.width {
            data.appendLE16(map.pixel(x: x, y: y).rgb565)
        }
        if padding > 0 {
            data.append(contentsOf: repeatElement(UInt8(0), count: padding))
        }
    }

    return data
}

private func makeRgbBmp(map: PixelMap, bitDepth: Int) -> Data {
    let bytesPerPixel = bitDepth / 8
    let rowBytes = map.width * bytesPerPixel
    let rowStride = ((rowBytes + 3) / 4) * 4
    let imageSize = rowStride * map.height
    let pixelOffset = 14 + 40
    let fileSize = pixelOffset + imageSize

    var data = Data()
    data.append(contentsOf: [0x42, 0x4d])
    data.appendLE32(UInt32(fileSize))
    data.appendLE16(0)
    data.appendLE16(0)
    data.appendLE32(UInt32(pixelOffset))
    data.appendLE32(40)
    data.appendLE32(UInt32(map.width))
    data.appendLE32(UInt32(map.height))
    data.appendLE16(1)
    data.appendLE16(UInt16(bitDepth))
    data.appendLE32(0)
    data.appendLE32(UInt32(imageSize))
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0)
    data.appendLE32(0)

    let padding = rowStride - rowBytes
    for y in stride(from: map.height - 1, through: 0, by: -1) {
        for x in 0..<map.width {
            data.append(contentsOf: map.pixel(x: x, y: y).bgr)
            if bitDepth == 32 {
                data.append(0)
            }
        }
        if padding > 0 {
            data.append(contentsOf: repeatElement(UInt8(0), count: padding))
        }
    }

    return data
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
