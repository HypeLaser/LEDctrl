import Foundation
import SigmaProtocol

let args = CommandLine.arguments.filter { $0 != "--" }
if args.dropFirst().contains("--list-effects") {
    for effect in allEffects() {
        let paddedName = effect.name.padding(toLength: 36, withPad: " ", startingAt: 0)
        let paddedID = String(effect.id).padding(toLength: 2, withPad: " ", startingAt: 0)
        let code = "0x" + String(effectCode(id: effect.id), radix: 16, uppercase: true).padding(toLength: 2, withPad: "0", startingAt: 0)
        print("\(paddedID)  \(paddedName)  code \(code)")
    }
    exit(0)
}

guard args.count >= 3 else {
    print("Usage: LEDSigmaSend <host> [--font normal7] [--color red|green|orange] [--mode fitted|marquee] [--in-id 1|--in move-left] [--out-id 1|--out jump-out] [--speed 2] [--hold 2] <text...>")
    print("       LEDSigmaSend --list-effects")
    exit(2)
}

let host = args[1]
var font = SigmaFont.normal7
var color = SigmaColor.red
var inEffectID = 1
var outEffectID = 1
var speedID = 2
var holdSeconds = 2
var wrapsText = true
var clearFirst = false
var words: [String] = []
var idx = 2
while idx < args.count {
    switch args[idx] {
    case "--font" where idx + 1 < args.count:
        font = SigmaFont(rawValue: args[idx + 1]) ?? font
        idx += 2
    case "--color" where idx + 1 < args.count:
        color = SigmaColor(rawValue: args[idx + 1]) ?? color
        idx += 2
    case "--in-id" where idx + 1 < args.count:
        inEffectID = Int(args[idx + 1]) ?? inEffectID
        idx += 2
    case "--out-id" where idx + 1 < args.count:
        outEffectID = Int(args[idx + 1]) ?? outEffectID
        idx += 2
    case "--in" where idx + 1 < args.count:
        inEffectID = effectID(named: args[idx + 1]) ?? inEffectID
        idx += 2
    case "--out" where idx + 1 < args.count:
        outEffectID = effectID(named: args[idx + 1]) ?? outEffectID
        idx += 2
    case "--speed" where idx + 1 < args.count:
        speedID = Int(args[idx + 1]) ?? speedID
        idx += 2
    case "--hold" where idx + 1 < args.count:
        holdSeconds = Int(args[idx + 1]) ?? holdSeconds
        idx += 2
    case "--mode" where idx + 1 < args.count:
        wrapsText = args[idx + 1].lowercased() != "marquee"
        idx += 2
    case "--clear-first":
        clearFirst = true
        idx += 1
    default:
        words.append(args[idx])
        idx += 1
    }
}

var client = SigmaClient(host: host)
do {
    if clearFirst {
        for step in try client.clearAll() { print(step) }
    }
    let options = SigmaTextOptions(
        inEffectCode: wrapsText ? effectCode(id: inEffectID) : UInt8(ascii: "1"),
        outEffectCode: wrapsText ? effectCode(id: outEffectID) : UInt8(ascii: "1"),
        speedCode: speedCode(id: speedID),
        holdSeconds: holdSeconds,
        wrapsText: wrapsText
    )
    let messageText = words.joined(separator: " ")
        .replacingOccurrences(of: "\\r", with: "\r")
        .replacingOccurrences(of: "\\n", with: "\n")
    let steps = try client.sendText(messageText, font: font, color: color, options: options)
    for step in steps {
        print(step)
    }
} catch {
    print("error: \(error)")
    exit(1)
}

private func effectCode(id: Int) -> UInt8 {
    UInt8(0x2f + max(0, min(48, id)))
}

private func speedCode(id: Int) -> UInt8 {
    UInt8(ascii: "0") + UInt8(max(0, min(6, id)))
}

private struct Effect {
    let id: Int
    let name: String

    var key: String {
        name
            .lowercased()
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .joined(separator: "-")
    }
}

private func allEffects() -> [Effect] {
    [
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
    ].enumerated().map { Effect(id: $0.offset, name: $0.element) }
}

private func effectID(named rawName: String) -> Int? {
    if let id = Int(rawName) {
        return max(0, min(48, id))
    }

    let key = rawName
        .lowercased()
        .replacingOccurrences(of: "_", with: "-")
        .replacingOccurrences(of: " ", with: "-")

    return allEffects().first { $0.key == key }?.id
}
