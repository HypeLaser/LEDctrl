import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    print("Usage: LEDConfigPatch <input-CONFIG.SYS> <output-CONFIG.SYS> <new-ip>")
    exit(2)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let newIP = args[3]

func parseIPv4(_ value: String) -> [UInt8]? {
    let parts = value.split(separator: ".")
    guard parts.count == 4 else { return nil }
    var bytes: [UInt8] = []
    for part in parts {
        guard let byte = UInt8(part) else { return nil }
        bytes.append(byte)
    }
    return bytes
}

guard let newBytes = parseIPv4(newIP) else {
    print("Invalid IPv4 address: \(newIP)")
    exit(2)
}

var data = try Data(contentsOf: inputURL)
guard data.count >= 0x28 else {
    print("CONFIG.SYS is too small to contain the Sigma IP field")
    exit(1)
}

let offset = 0x24
let oldBytes = Array(data[offset..<(offset + 4)])
let storedBytes = Array(newBytes.reversed())
data.replaceSubrange(offset..<(offset + 4), with: storedBytes)
try data.write(to: outputURL, options: .atomic)

func dotted(_ bytes: [UInt8]) -> String {
    bytes.map(String.init).joined(separator: ".")
}

print("Patched \(inputURL.path) -> \(outputURL.path)")
print("IP field @ 0x24: \(dotted(oldBytes.reversed())) -> \(newIP)")
print("Stored bytes: \(storedBytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
