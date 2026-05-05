import SigmaProtocol
import Darwin
import Foundation

struct Config {
    var host: String
    var port: UInt16 = 9520
    var minor: UInt8? = 0x02
    var sequenceStart: UInt16 = 0x100
    var idleTimeoutMs: Int = 1200
    var totalTimeoutMs: Int = 20000
    var outputDir: String?
    var scan: Bool = false
    var scanStart: UInt8 = 0x00
    var scanEnd: UInt8 = 0x40
}

enum DumpError: Error, CustomStringConvertible {
    case usage(String)
    case socket(String)
    case io(String)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .socket(let message): return message
        case .io(let message): return message
        }
    }
}

struct FrameSummary {
    let index: Int
    let byteCount: Int
    let commandMajor: UInt8?
    let commandMinor: UInt8?
    let status: UInt16?
    let descriptorWords: Int
    let headerBytes: Int
    let extractedBodyBytes: Int
}

func parseConfig() throws -> Config {
    var args = CommandLine.arguments
    args.removeFirst()
    guard !args.isEmpty else {
        throw DumpError.usage(usageText)
    }
    if args[0] == "--help" || args[0] == "-h" {
        throw DumpError.usage(usageText)
    }

    var cfg = Config(host: args.removeFirst())
    var idx = 0
    while idx < args.count {
        switch args[idx] {
        case "--port":
            guard idx + 1 < args.count, let value = UInt16(args[idx + 1]) else {
                throw DumpError.usage("Invalid --port value")
            }
            cfg.port = value
            idx += 2
        case "--minor":
            guard idx + 1 < args.count else { throw DumpError.usage("Missing --minor value") }
            cfg.minor = try parseByte(args[idx + 1])
            idx += 2
        case "--seq":
            guard idx + 1 < args.count, let value = UInt16(args[idx + 1]) else {
                throw DumpError.usage("Invalid --seq value")
            }
            cfg.sequenceStart = value
            idx += 2
        case "--idle-ms":
            guard idx + 1 < args.count, let value = Int(args[idx + 1]), value >= 100 else {
                throw DumpError.usage("Invalid --idle-ms value (min 100)")
            }
            cfg.idleTimeoutMs = value
            idx += 2
        case "--total-ms":
            guard idx + 1 < args.count, let value = Int(args[idx + 1]), value >= 500 else {
                throw DumpError.usage("Invalid --total-ms value (min 500)")
            }
            cfg.totalTimeoutMs = value
            idx += 2
        case "--out":
            guard idx + 1 < args.count else { throw DumpError.usage("Missing --out value") }
            cfg.outputDir = args[idx + 1]
            idx += 2
        case "--scan":
            cfg.scan = true
            cfg.minor = nil
            idx += 1
        case "--scan-range":
            guard idx + 1 < args.count else { throw DumpError.usage("Missing --scan-range value") }
            let parts = args[idx + 1].split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw DumpError.usage("Expected --scan-range <start-end>") }
            cfg.scanStart = try parseByte(String(parts[0]))
            cfg.scanEnd = try parseByte(String(parts[1]))
            if cfg.scanStart > cfg.scanEnd {
                swap(&cfg.scanStart, &cfg.scanEnd)
            }
            idx += 2
        case "--help", "-h":
            throw DumpError.usage(usageText)
        default:
            throw DumpError.usage("Unknown argument: \(args[idx])\n\n\(usageText)")
        }
    }

    return cfg
}

func parseByte(_ text: String) throws -> UInt8 {
    let cleaned = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
    guard let value = UInt8(cleaned, radix: 16) ?? UInt8(cleaned) else {
        throw DumpError.usage("Invalid byte value: \(text)")
    }
    return value
}

func makePayload(sequence: UInt16, major: UInt8, minor: UInt8) -> Data {
    var payload = Data()
    payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
    payload.append(contentsOf: le16(sequence))
    payload.append(contentsOf: [major, minor, 0x00, 0x00])
    return payload
}

func makeFrame(_ payload: Data) -> Data {
    let crc = x25(payload)
    var frame = Data([0x55, 0xa3, UInt8((crc >> 8) & 0xff), UInt8(crc & 0xff)])
    frame.append(payload)
    return frame
}

func le16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
}

func x25(_ data: Data) -> UInt16 {
    var crc: UInt16 = 0xffff
    for byte in data {
        crc = crcTable[Int((UInt8(crc & 0xff) ^ byte))] ^ (crc >> 8)
    }
    return ~crc
}

let crcTable: [UInt16] = (0..<256).map { value in
    var crc = UInt16(value)
    for _ in 0..<8 {
        if crc & 1 == 1 {
            crc = (crc >> 1) ^ 0x8408
        } else {
            crc >>= 1
        }
    }
    return crc
}

func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func openUDPSocket(host: String, port: UInt16, timeoutMs: Int) throws -> Int32 {
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard fd >= 0 else {
        throw DumpError.socket("socket() failed: \(String(cString: strerror(errno)))")
    }

    var timeout = timeval(
        tv_sec: timeoutMs / 1000,
        tv_usec: __darwin_suseconds_t((timeoutMs % 1000) * 1000)
    )
    let setRecv = withUnsafePointer(to: &timeout) {
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
    }
    guard setRecv == 0 else {
        close(fd)
        throw DumpError.socket("setsockopt(SO_RCVTIMEO) failed: \(String(cString: strerror(errno)))")
    }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    let ipResult = host.withCString { cString in
        inet_pton(AF_INET, cString, &addr.sin_addr)
    }
    guard ipResult == 1 else {
        close(fd)
        throw DumpError.socket("inet_pton failed for host \(host)")
    }

    let connectResult = withUnsafePointer(to: &addr) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
            connect(fd, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connectResult == 0 else {
        close(fd)
        throw DumpError.socket("connect() failed: \(String(cString: strerror(errno)))")
    }

    return fd
}

func sendFrame(_ frame: Data, fd: Int32) throws {
    let sent = frame.withUnsafeBytes { bytes in
        send(fd, bytes.baseAddress, frame.count, 0)
    }
    guard sent == frame.count else {
        throw DumpError.socket("send() failed: wrote \(sent)/\(frame.count) bytes, errno \(errno)")
    }
}

func receiveFrames(fd: Int32, totalTimeoutMs: Int, idleTimeoutMs: Int) throws -> [Data] {
    var frames: [Data] = []
    let started = Date()
    var lastReceive = started
    var buffer = [UInt8](repeating: 0, count: 65535)

    while Date().timeIntervalSince(started) * 1000 < Double(totalTimeoutMs) {
        let count = recv(fd, &buffer, buffer.count, 0)
        if count > 0 {
            frames.append(Data(buffer.prefix(count)))
            lastReceive = Date()
            continue
        }
        if count == 0 {
            break
        }
        if errno == EAGAIN || errno == EWOULDBLOCK {
            if !frames.isEmpty, Date().timeIntervalSince(lastReceive) * 1000 >= Double(idleTimeoutMs) {
                break
            }
            continue
        }
        if errno == ECONNREFUSED {
            break
        }
        throw DumpError.socket("recv() failed: \(String(cString: strerror(errno)))")
    }
    return frames
}

func parseResponse(_ frame: Data, index: Int) -> (FrameSummary, Data?) {
    let commandMajor = frame.count > 12 ? frame[12] : nil
    let commandMinor = frame.count > 13 ? frame[13] : nil
    let descriptorWords = frame.count > 14 ? Int(frame[14]) : 0
    let status: UInt16? = frame.count > 17 ? (UInt16(frame[16]) | (UInt16(frame[17]) << 8)) : nil

    // Based on observed vendor responses, byte 20 is the earliest stable start of variable data.
    let bodyOffset = 20
    let body: Data? = frame.count > bodyOffset ? frame.subdata(in: bodyOffset..<frame.count) : nil

    return (
        FrameSummary(
            index: index,
            byteCount: frame.count,
            commandMajor: commandMajor,
            commandMinor: commandMinor,
            status: status,
            descriptorWords: descriptorWords,
            headerBytes: bodyOffset,
            extractedBodyBytes: body?.count ?? 0
        ),
        body
    )
}

func makeOutputDirectory(_ configured: String?) throws -> URL {
    let fm = FileManager.default
    if let configured {
        let url = URL(fileURLWithPath: configured, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    let stamp = DateFormatter.firmwareStamp.string(from: Date()) + "-\(Int(Date().timeIntervalSince1970 * 1000) % 1000)"
    let defaultPath = Paths.projectRoot.appendingPathComponent("analysis/runtime/firmware-dump-\(stamp)").path()
    let url = URL(fileURLWithPath: defaultPath, isDirectory: true)
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeDump(commandMajor: UInt8, commandMinor: UInt8, frames: [Data], outputDir: URL) throws {
    var summaryLines: [String] = []
    summaryLines.append(String(format: "command=%02X:%02X", commandMajor, commandMinor))
    summaryLines.append("frames=\(frames.count)")
    summaryLines.append("")

    var extracted = Data()
    for (idx, frame) in frames.enumerated() {
        let (summary, body) = parseResponse(frame, index: idx + 1)
        let rawURL = outputDir.appendingPathComponent(String(format: "frame-%03d.bin", idx + 1))
        try frame.write(to: rawURL)

        if let body, !body.isEmpty {
            extracted.append(body)
            let bodyURL = outputDir.appendingPathComponent(String(format: "frame-%03d.body.bin", idx + 1))
            try body.write(to: bodyURL)
        }

        let statusText = summary.status.map { String(format: "0x%04X", $0) } ?? "n/a"
        let commandText: String
        if let major = summary.commandMajor, let minor = summary.commandMinor {
            commandText = String(format: "%02X:%02X", major, minor)
        } else {
            commandText = "n/a"
        }
        summaryLines.append(
            "frame \(summary.index): bytes=\(summary.byteCount) cmd=\(commandText) status=\(statusText) descWords=\(summary.descriptorWords) headerBytes=\(summary.headerBytes) bodyBytes=\(summary.extractedBodyBytes)"
        )
    }

    if !extracted.isEmpty {
        try extracted.write(to: outputDir.appendingPathComponent("payload.concat.bin"))
        summaryLines.append("")
        summaryLines.append("payload.concat.bin bytes=\(extracted.count)")
        summaryLines.append("payload head=\(hex(extracted.prefix(64)))")
    }

    let summary = summaryLines.joined(separator: "\n") + "\n"
    try summary.data(using: .utf8)?.write(to: outputDir.appendingPathComponent("summary.txt"))
}

func readCommand(host: String, port: UInt16, sequence: UInt16, major: UInt8, minor: UInt8, totalTimeoutMs: Int, idleTimeoutMs: Int) throws -> [Data] {
    let fd = try openUDPSocket(host: host, port: port, timeoutMs: max(200, min(idleTimeoutMs, 4000)))
    defer { close(fd) }
    let payload = makePayload(sequence: sequence, major: major, minor: minor)
    try sendFrame(makeFrame(payload), fd: fd)
    return try receiveFrames(fd: fd, totalTimeoutMs: totalTimeoutMs, idleTimeoutMs: idleTimeoutMs)
}

func runScan(_ cfg: Config) throws {
    print("Scanning \(cfg.host):\(cfg.port) commands 01:\(String(format: "%02X", cfg.scanStart))..01:\(String(format: "%02X", cfg.scanEnd))")
    var sequence = cfg.sequenceStart
    for minor in cfg.scanStart...cfg.scanEnd {
        let frames = try readCommand(
            host: cfg.host,
            port: cfg.port,
            sequence: sequence,
            major: 0x01,
            minor: minor,
            totalTimeoutMs: min(cfg.totalTimeoutMs, 5000),
            idleTimeoutMs: min(cfg.idleTimeoutMs, 900)
        )
        sequence &+= 1

        if let first = frames.first {
            let (summary, _) = parseResponse(first, index: 1)
            let statusText = summary.status.map { String(format: "0x%04X", $0) } ?? "n/a"
            print(String(format: "01:%02X -> frames=%d firstStatus=%@ firstBytes=%d", minor, frames.count, statusText, summary.byteCount))
        } else {
            print(String(format: "01:%02X -> no response", minor))
        }
    }
}

let usageText = """
Usage:
  LEDFirmwareDump <host> [options]

Options:
  --port <port>             UDP port (default: 9520)
  --minor <value>           Minor command for major 0x01 (default: 0x02)
  --seq <value>             Starting sequence (default: 0x100)
  --idle-ms <ms>            Stop when idle after first response (default: 1200)
  --total-ms <ms>           Absolute receive timeout (default: 20000)
  --out <dir>               Output directory
  --scan                    Scan command family 0x01:<minor>
  --scan-range <start-end>  Scan range (default: 0x00-0x40)

Notes:
  - This tool targets read-style commands recovered from vendor DLL wrappers.
  - For read-family tests, common candidates are 0x01:0x02, 0x01:0x04, 0x01:0x0A, 0x01:0x12.
"""

do {
    let cfg = try parseConfig()
    if cfg.scan {
        try runScan(cfg)
        exit(0)
    }

    guard let minor = cfg.minor else {
        throw DumpError.usage("Missing --minor value")
    }

    print(String(format: "Sending read command %02X:%02X to %@:%d", 0x01, minor, cfg.host, cfg.port))
    let frames = try readCommand(
        host: cfg.host,
        port: cfg.port,
        sequence: cfg.sequenceStart,
        major: 0x01,
        minor: minor,
        totalTimeoutMs: cfg.totalTimeoutMs,
        idleTimeoutMs: cfg.idleTimeoutMs
    )

    if frames.isEmpty {
        print("No response frames.")
        exit(1)
    }

    let outputDir = try makeOutputDirectory(cfg.outputDir)
    try writeDump(commandMajor: 0x01, commandMinor: minor, frames: frames, outputDir: outputDir)
    print("Captured \(frames.count) frame(s)")
    print("Output: \(outputDir.path)")
} catch {
    if case DumpError.usage(let text) = error {
        fputs("\(text)\n", stderr)
        exit(2)
    }
    fputs("LEDFirmwareDump error: \(error)\n", stderr)
    exit(2)
}

extension DateFormatter {
    static let firmwareStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
