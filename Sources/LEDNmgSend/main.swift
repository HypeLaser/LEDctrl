import Foundation
import SigmaProtocol

let args = CommandLine.arguments.filter { $0 != "--" }

func usage() {
    print("Usage: LEDNmgSend <host> [--type text|picture|flw] [--filename <remoteName>] [--editor-sequence] [--sequence <file>] <file>")
    print("       LEDNmgSend <host> --delete <remotePath>")
}

guard args.count >= 3 else {
    usage()
    exit(2)
}

let host = args[1]
var fileType = SigmaProgramFileType.text
var useEditorSequence = false
var sequencePath: String?
var payloadLengthOverride: Int?
var remoteFilename: String?
var deletePath: String?
var path: String?
var idx = 2

while idx < args.count {
    switch args[idx] {
    case "--type" where idx + 1 < args.count:
        fileType = SigmaProgramFileType(rawValue: args[idx + 1].lowercased()) ?? fileType
        idx += 2
    case "--editor-sequence":
        useEditorSequence = true
        idx += 1
    case "--sequence" where idx + 1 < args.count:
        sequencePath = args[idx + 1]
        idx += 2
    case "--payload-len" where idx + 1 < args.count:
        payloadLengthOverride = Int(args[idx + 1])
        idx += 2
    case "--filename" where idx + 1 < args.count:
        remoteFilename = args[idx + 1]
        idx += 2
    case "--delete" where idx + 1 < args.count:
        deletePath = args[idx + 1]
        idx += 2
    case "--list":
        var client = SigmaClient(host: host)
        do {
            let flag: UInt8 = (idx + 1 < args.count) ? (UInt8(args[idx + 1]) ?? 1) : 1
            let res = try client.listFiles(flag: flag)
            print("count=\(res.count) names=\(res.names)")
            print("raw hex: \(res.raw.map { String(format: "%02x", $0) }.joined(separator: " "))")
            exit(0)
        } catch {
            print("error: \(error)")
            exit(1)
        }
    case "--list-path" where idx + 1 < args.count:
        var client = SigmaClient(host: host)
        do {
            let res = try client.listFiles(flag: 0, path: args[idx + 1])
            print("count=\(res.count) names=\(res.names)")
            print("raw hex: \(res.raw.map { String(format: "%02x", $0) }.joined(separator: " "))")
            exit(0)
        } catch {
            print("error: \(error)")
            exit(1)
        }
    default:
        path = args[idx]
        idx += 1
    }
}

if let deletePath {
    do {
        var client = SigmaClient(host: host)
        // Pause playback first — sign locks open files (status 0x9015).
        if let pause = try? client.pausePlay() { print(pause) }
        let step = try client.deleteFile(path: deletePath)
        print(step)
        exit(0)
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

guard let path else {
    usage()
    exit(2)
}

do {
    let content = try Data(contentsOf: URL(fileURLWithPath: path))
    var client = SigmaClient(host: host)
    let steps: [String]
    if useEditorSequence {
        let seqData = try sequencePath.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let effectiveLength = payloadLengthOverride ?? seqData.flatMap { sequencePayloadLength(for: "temp.Nmg", in: $0) }
        steps = try client.sendEditorProgramNmg(
            content,
            sequenceFileOverride: seqData,
            payloadLengthOverride: effectiveLength
        )
    } else {
        steps = try client.sendNmg(
            content,
            filename: remoteFilename ?? "temp.Nmg",
            fileType: fileType
        )
    }
    for step in steps {
        print(step)
    }
} catch {
    print("error: \(error)")
    exit(1)
}

private func sequencePayloadLength(for filename: String, in sequence: Data) -> Int? {
    guard let range = sequence.firstRange(of: Data(filename.utf8)) else { return nil }
    let start = range.lowerBound
    guard start >= 2 else { return nil }
    return Int(sequence[start - 2]) | (Int(sequence[start - 1]) << 8)
}
