import Foundation

public func sigmaX25(_ data: Data) -> UInt16 {
    var crc: UInt16 = 0xffff
    for byte in data {
        crc = sigmaCRCTable[Int((UInt8(crc & 0xff) ^ byte))] ^ (crc >> 8)
    }
    return ~crc
}

private let sigmaCRCTable: [UInt16] = (0..<256).map { value in
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

public extension Data {
    init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let value = UInt8(clean[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        self = bytes
    }

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

    func le16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func le32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func setLE16(_ value: UInt16, at offset: Int) {
        guard offset + 2 <= count else { return }
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
    }

    mutating func setLE32(_ value: UInt32, at offset: Int) {
        guard offset + 4 <= count else { return }
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    func chunked(maxSize: Int) -> [Data] {
        guard !isEmpty else { return [Data()] }
        var chunks: [Data] = []
        var offset = 0
        while offset < count {
            let end = Swift.min(offset + maxSize, count)
            chunks.append(subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    mutating func rewriteSigmaFrameCRC() {
        guard count >= 5 else { return }
        let payload = self.dropFirst(4)
        let crc = sigmaX25(Data(payload))
        self[2] = UInt8((crc >> 8) & 0xff)
        self[3] = UInt8(crc & 0xff)
    }
}

public func le16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
}

public func le32(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 24) & 0xff)
    ]
}
