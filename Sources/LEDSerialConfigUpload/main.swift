import Darwin
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    print("Usage: LEDSerialConfigUpload <serial-path> <baud> <CONFIG.SYS>")
    exit(2)
}

let path = args[1]
let baud = Int(args[2]) ?? 9600
let configURL = URL(fileURLWithPath: args[3])
let content = try Data(contentsOf: configURL)

let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
guard fd >= 0 else {
    print("Could not open \(path): \(String(cString: strerror(errno)))")
    exit(1)
}
defer { close(fd) }

var options = termios()
guard tcgetattr(fd, &options) == 0 else {
    print("Could not read serial settings: \(String(cString: strerror(errno)))")
    exit(1)
}

cfmakeraw(&options)
let speed: speed_t
switch baud {
case 9600: speed = speed_t(B9600)
case 19200: speed = speed_t(B19200)
case 115200: speed = speed_t(B115200)
default: speed = speed_t(B9600)
}
cfsetspeed(&options, speed)
options.c_cflag |= tcflag_t(CLOCAL | CREAD)
guard tcsetattr(fd, TCSANOW, &options) == 0 else {
    print("Could not set serial settings: \(String(cString: strerror(errno)))")
    exit(1)
}

func transact(_ payload: Data, context: String) throws -> Data {
    let frame = makeFrame(payload)
    let written = frame.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return -1 }
        return write(fd, baseAddress, frame.count)
    }
    guard written == frame.count else {
        throw UploadError.message("\(context): wrote \(written)/\(frame.count) bytes")
    }

    var received = Data()
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        var buffer = [UInt8](repeating: 0, count: 2048)
        let bufferCount = buffer.count
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return read(fd, baseAddress, bufferCount)
        }
        if count > 0 {
            received.append(contentsOf: buffer.prefix(count))
            if received.count >= 18 {
                return received
            }
        } else {
            usleep(50_000)
        }
    }
    throw UploadError.message("\(context): timeout; received \(hex(received))")
}

func sendConfig(_ content: Data) throws {
    let chunks = content.chunked(maxSize: 768)
    var sequence: UInt16 = 0x100
    for (index, chunk) in chunks.enumerated() {
        let totalPackets = chunks.count
        var descriptor = fixedBytes("CONFIG.SYS", count: 12)
        descriptor += le32(UInt32(content.count))
        descriptor += le16(768)
        descriptor += le16(UInt16(totalPackets))
        descriptor += le16(UInt16(index + 1))
        descriptor += [0x00, 0x00]

        var payload = Data()
        payload.append(contentsOf: le32(UInt32(chunk.count)))
        payload.append(contentsOf: [0x01, 0x01])
        payload.append(contentsOf: le16(sequence))
        sequence &+= 1
        payload.append(contentsOf: [0x02, 0x02])
        payload.append(contentsOf: le16(UInt16(descriptor.count / 4)))
        payload.append(contentsOf: descriptor)
        payload.append(chunk)

        let context = "CONFIG.SYS chunk \(index + 1)/\(totalPackets)"
        let response = try transact(payload, context: context)
        try requireOK(response, context: context)
        print("\(context): OK")
    }
}

do {
    try sendConfig(content)
    print("CONFIG.SYS serial upload complete")
} catch {
    print("Serial config upload failed: \(error)")
    exit(1)
}

enum UploadError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

func makeFrame(_ payload: Data) -> Data {
    let crc = x25(payload)
    var frame = Data([0x55, 0xa3, UInt8((crc >> 8) & 0xff), UInt8(crc & 0xff)])
    frame.append(payload)
    return frame
}

func requireOK(_ response: Data, context: String) throws {
    guard response.count >= 18 else {
        throw UploadError.message("\(context): short response \(hex(response))")
    }
    let status = UInt16(response[16]) | (UInt16(response[17]) << 8)
    guard status == 0x9000 else {
        throw UploadError.message("\(context): status 0x\(String(format: "%04X", status)); response \(hex(response))")
    }
}

func fixedBytes(_ string: String, count: Int) -> [UInt8] {
    var bytes = Array(string.utf8.prefix(count))
    if bytes.count < count {
        bytes.append(contentsOf: repeatElement(0, count: count - bytes.count))
    }
    return bytes
}

func le16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
}

func le32(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 24) & 0xff)
    ]
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

extension Data {
    func chunked(maxSize: Int) -> [Data] {
        guard !isEmpty else { return [Data()] }
        var chunks: [Data] = []
        var offset = 0
        while offset < count {
            let nextOffset = Swift.min(offset + maxSize, count)
            chunks.append(subdata(in: offset..<nextOffset))
            offset = nextOffset
        }
        return chunks
    }
}
