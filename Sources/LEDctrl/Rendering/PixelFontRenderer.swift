import Foundation
import SigmaProtocol

enum PixelFontRenderer {
    private static let characterGap = 0

    struct RenderedPixels {
        let pixels: [[Bool]]
        let characterIndexes: [[Int?]]
    }

    static func render(text: String, style: AppFont, width: Int, height: Int, xOffset: Int = 0, yOffset: Int = 0) -> RenderedPixels {
        render(text: text, baseStyle: style, styleRuns: [], width: width, height: height, xOffset: xOffset, yOffset: yOffset)
    }

    static func render(text: String, baseStyle: AppFont, styleRuns: [CanvasStyleRun], width: Int, height: Int, xOffset: Int = 0, yOffset: Int = 0) -> RenderedPixels {
        var pixels = Array(repeating: Array(repeating: false, count: width), count: height)
        var characterIndexes = Array(repeating: Array<Int?>(repeating: nil, count: width), count: height)
        var cursor = xOffset
        var visibleIndex = 0

        for character in text {
            if character == "\n" || character == "\r" { break }
            let style = fontFor(characterIndex: visibleIndex, baseStyle: baseStyle, styleRuns: styleRuns)
            let glyph = glyphRows(for: character, style: style)
            let glyphYOffset = max(0, (height - glyph.count) / 2) + yOffset
            for (gy, row) in glyph.enumerated() where glyphYOffset + gy < height {
                for (gx, bit) in row.enumerated() {
                    let px = cursor + gx
                    let py = glyphYOffset + gy
                    if bit == "1", px >= 0, px < width, py >= 0, py < height {
                        pixels[py][px] = true
                        characterIndexes[py][px] = visibleIndex
                    }
                }
            }
            cursor += advance(for: character, glyph: glyph, style: style)
            visibleIndex += 1
            if cursor >= width { break }
        }
        return RenderedPixels(pixels: pixels, characterIndexes: characterIndexes)
    }

    static func textWidth(_ text: String, style: AppFont) -> Int {
        textWidth(text, baseStyle: style, styleRuns: [])
    }

    static func textWidth(_ text: String, baseStyle: AppFont, styleRuns: [CanvasStyleRun]) -> Int {
        var width = 0
        for (index, character) in text.enumerated() {
            if character == "\n" || character == "\r" { break }
            let style = fontFor(characterIndex: index, baseStyle: baseStyle, styleRuns: styleRuns)
            let glyph = glyphRows(for: character, style: style)
            width += advance(for: character, glyph: glyph, style: style)
        }
        return max(0, width - characterGap)
    }

    static func fontFor(characterIndex: Int, baseStyle: AppFont, styleRuns: [CanvasStyleRun]) -> AppFont {
        let token = styleRuns.last {
            characterIndex >= $0.location &&
            characterIndex < $0.location + $0.length &&
            ["{font5}", "{font7}"].contains($0.token.lowercased())
        }?.token.lowercased()
        switch token {
        case "{font5}": return .normal5
        case "{font7}": return .normal7
        default: return baseStyle
        }
    }

    static func advance(for character: Character, glyph: [String], style: AppFont) -> Int {
        return (glyph.first?.count ?? 0) + characterGap
    }

    static func glyphRows(for character: Character, style: AppFont) -> [String] {
        VendorBitmapFont.glyphRows(for: character, style: style) ?? fallbackGlyphRows(for: character, style: style)
    }

    private static func fallbackGlyphRows(for character: Character, style: AppFont) -> [String] {
        switch style {
        case .normal5:
            return fiveHigh(glyph5x7[character] ?? glyph5x7["?"]!)
        case .normal7:
            return glyph5x7[character] ?? glyph5x7["?"]!
        }
    }

    private enum VendorBitmapFont {
        private static let normal5 = load(name: "Normal5.fnt")
        private static let normal7 = load(name: "Normal7.fnt")

        static func glyphRows(for character: Character, style: AppFont) -> [String]? {
            guard let scalar = character.unicodeScalars.first,
                  scalar.value < 256 else {
                return nil
            }
            let code = Int(scalar.value)
            switch style {
            case .normal5:
                return glyphRows(in: normal5, code: code, width: 5, height: 5)
            case .normal7:
                return glyphRows(in: normal7, code: code, width: 6, height: 7)
            }
        }

        private static func load(name: String) -> Data? {
            try? Data(contentsOf: Paths.fontDirectory.appendingPathComponent(name))
        }

        private static func glyphRows(in data: Data?, code: Int, width: Int, height: Int) -> [String]? {
            guard let data else { return nil }
            let offset = code * height
            guard offset + height <= data.count else { return nil }
            return data[offset..<(offset + height)].map { byte in
                (0..<width).map { bitIndex in
                    byte & (0x80 >> UInt8(bitIndex)) == 0 ? "0" : "1"
                }.joined()
            }
        }
    }

    private static func fiveHigh(_ rows: [String]) -> [String] {
        guard rows.count == 7 else { return rows }
        return [rows[0], rows[1], rows[3], rows[5], rows[6]]
    }

    private static let glyph3x5: [Character: [String]] = [
        " ": ["000", "000", "000", "000", "000"],
        "?": ["111", "001", "011", "000", "010"]
    ]

    private static let glyph5x7: [Character: [String]] = [
        " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
        "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"]
    ].merging(glyph5x7Letters, uniquingKeysWith: { current, _ in current })

    private static let glyph5x7Letters: [Character: [String]] = [
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
        "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
        "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
        ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
        ",": ["00000", "00000", "00000", "00000", "01100", "00100", "01000"],
        "'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
        "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
        ">": ["10000", "01000", "00100", "00010", "00100", "01000", "10000"],
        "<": ["00001", "00010", "00100", "01000", "00100", "00010", "00001"],
        "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
        "@": ["01110", "10001", "10111", "10101", "10111", "10000", "01111"],
        "#": ["01010", "01010", "11111", "01010", "11111", "01010", "01010"],
        "$": ["00100", "01111", "10100", "01110", "00101", "11110", "00100"],
        "£": ["00110", "01001", "01000", "11100", "01000", "01000", "11111"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
        "^": ["00100", "01010", "10001", "00000", "00000", "00000", "00000"],
        "&": ["01100", "10010", "10100", "01000", "10101", "10010", "01101"],
        "*": ["00100", "10101", "01110", "11111", "01110", "10101", "00100"],
        "(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
        ")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
        "_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
        "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
        "=": ["00000", "00000", "11111", "00000", "11111", "00000", "00000"],
        "[": ["01110", "01000", "01000", "01000", "01000", "01000", "01110"],
        "]": ["01110", "00010", "00010", "00010", "00010", "00010", "01110"]
    ]
}
