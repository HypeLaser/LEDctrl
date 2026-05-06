import Foundation
import Network

public struct SigmaClient {
    public let host: String
    public let port: UInt16
    private var sequence: UInt16 = 0x100
    private var clockHandshakeDone: Bool = false
    public var autoSetClockOnSend: Bool = true

    public init(host: String, port: UInt16 = 9520) {
        self.host = host
        self.port = port
    }

    /// Sigma treats an invalid RTC as a render gate — playback engine refuses
    /// to render until the clock is set. Called once per instance before the
    /// first message-send, best-effort: a failure here is logged on stderr but
    /// does not block the send.
    private mutating func ensureClock() {
        guard autoSetClockOnSend, !clockHandshakeDone else { return }
        do {
            try setSignTime()
            clockHandshakeDone = true
        } catch {
            FileHandle.standardError.write(Data("warning: setSignTime handshake failed: \(error)\n".utf8))
        }
    }

    public mutating func sendText(
        _ text: String,
        font: SigmaFont = .normal7,
        color: SigmaColor = .red,
        options: SigmaTextOptions = .default,
        editorFontCompat: Bool = false
    ) throws -> [String] {
        ensureClock()
        var steps: [String] = []
        steps.append(try simpleCommand(major: 0x04, minor: 0x01))
        let message = makeNmg(text: text, font: font, color: color, options: options, editorFontCompat: editorFontCompat)
        debugDump(message, filename: editorFontCompat ? "last-send-editor-font.Nmg" : "last-send-stable.Nmg")
        steps.append(try sendFile(name: "D\0temp.Nmg", content: message, command: 0x04))
        steps.append(try commit(path: "D:\\T\\temp.Nmg", content: message))

        let sequenceFile = makeSequenceFile(messageLength: message.count, nmgPayload: message)
        steps.append(try sendSequenceFile(sequenceFile))
        steps.append(try simpleCommand(major: 0x04, minor: 0x02))
        return steps
    }

    public mutating func sendEditorText(
        _ text: String,
        font: SigmaFont = .normal7,
        color: SigmaColor = .red,
        options: SigmaTextOptions = .default
    ) throws -> [String] {
        ensureClock()
        var steps: [String] = []
        steps.append(try simpleCommand(major: 0x04, minor: 0x01))
        let message = makeEditorNmg(text: text, font: font, color: color, options: options)
        steps.append(try sendFile(name: "D\0temp.Nmg", content: message, command: 0x04))
        steps.append(try commit(path: "D:\\T\\temp.Nmg", content: message))
        steps.append(try sendSequenceFile(makeEditorSequenceFile()))
        steps.append(try simpleCommand(major: 0x04, minor: 0x02))
        return steps
    }

    public mutating func sendTextProgram(
        _ entries: [SigmaTextProgramEntry],
        editorFontCompat: Bool = false
    ) throws -> [String] {
        let validEntries = entries.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validEntries.isEmpty else { return [] }

        ensureClock()
        var steps: [String] = []
        steps.append(try simpleCommand(major: 0x04, minor: 0x01))

        var sequenceEntries: [SigmaSequenceEntry] = []
        for (index, entry) in validEntries.enumerated() {
            let filename = String(format: "ROW%03d.Nmg", index + 1)
            let message = makeNmg(
                text: entry.text,
                font: entry.font,
                color: entry.color,
                options: entry.options,
                editorFontCompat: editorFontCompat
            )
            steps.append(try sendFile(name: "D\0\(filename)", content: message, command: 0x04))
            steps.append(try commit(path: "D:\\T\\\(filename)", content: message))
            sequenceEntries.append(
                SigmaSequenceEntry(
                    filename: filename,
                    length: message.count,
                    fileType: .text,
                    driveCode: UInt8(ascii: "D"),
                    nmgPayload: message
                )
            )
        }

        let sequenceFile = makeSequenceFile(entries: sequenceEntries)
        steps.append(try sendSequenceFile(sequenceFile))
        steps.append(try simpleCommand(major: 0x04, minor: 0x02))
        return steps
    }

    public mutating func sendNmg(
        _ content: Data,
        filename: String = "temp.Nmg",
        fileType: SigmaProgramFileType = .text
    ) throws -> [String] {
        let placement = filePlacement(for: fileType)
        let uploadDrive = (fileType == .flw) ? "D" : placement.drive
        ensureClock()
        var steps: [String] = []
        steps.append(
            "program routing: type=\(fileType.rawValue) upload=\(uploadDrive):\\0\(filename) commit=\(placement.drive):\\\(placement.folder)\\\(filename) seq=\(Character(UnicodeScalar(placement.driveCode)))/\(Character(UnicodeScalar(fileType.code)))"
        )
        steps.append("payload header: \(payloadHeaderSummary(content))")
        steps.append(try simpleCommand(major: 0x04, minor: 0x01))
        steps.append(try sendFile(name: "\(uploadDrive)\0\(filename)", content: content, command: 0x04))
        steps.append(try commit(path: "\(placement.drive):\\\(placement.folder)\\\(filename)", content: content))

        let sequenceFile = makeSequenceFile(
            messageLength: content.count,
            filename: filename,
            fileType: fileType,
            driveCode: placement.driveCode,
            nmgPayload: fileType == .flw ? nil : content
        )
        debugDump(sequenceFile, filename: "last-send-sequence.sys")
        steps.append("sequence header: \(sequenceHeaderSummary(sequenceFile))")
        steps.append(try sendSequenceFile(sequenceFile))
        steps.append(try simpleCommand(major: 0x04, minor: 0x02))
        return steps
    }

    public mutating func sendEditorProgramNmg(
        _ content: Data,
        filename: String = "temp.Nmg",
        sequenceFileOverride: Data? = nil,
        payloadLengthOverride: Int? = nil
    ) throws -> [String] {
        ensureClock()
        var steps: [String] = []
        let sequenceFile = sequenceFileOverride ?? makeEditorSequenceFile()
        let payload: Data
        if let payloadLengthOverride, payloadLengthOverride > 0, payloadLengthOverride <= content.count {
            payload = content.prefix(payloadLengthOverride)
        } else {
            payload = content
        }

        steps.append(try simpleCommand(major: 0x04, minor: 0x01))
        steps.append(try sendFile(name: "D\0\(filename)", content: payload, command: 0x04))
        steps.append(try commit(path: "D:\\T\\\(filename)", content: payload))
        debugDump(sequenceFile, filename: "last-send-editor-sequence.sys")
        steps.append(try sendSequenceFile(sequenceFile))
        steps.append(try simpleCommand(major: 0x04, minor: 0x02))
        return steps
    }

    public mutating func sendEditorProgramEntries(
        _ entries: [SigmaBinaryProgramEntry],
        sequenceTimingCode: UInt8? = nil
    ) throws -> [String] {
        let validEntries = entries.filter { !$0.content.isEmpty }
        guard !validEntries.isEmpty else { return [] }

        ensureClock()
        var steps: [String] = []
        steps.append(try simpleCommand(major: 0x04, minor: 0x01))

        var sequenceEntries: [SigmaSequenceEntry] = []
        for entry in validEntries {
            let payload: Data
            if let payloadLength = entry.payloadLengthOverride,
               payloadLength > 0,
               payloadLength <= entry.content.count {
                payload = entry.content.prefix(payloadLength)
            } else {
                payload = entry.content
            }
            steps.append(try sendFile(name: "D\0\(entry.filename)", content: payload, command: 0x04))
            steps.append(try commit(path: "D:\\T\\\(entry.filename)", content: payload))
            sequenceEntries.append(
                SigmaSequenceEntry(
                    filename: entry.filename,
                    length: payload.count,
                    fileType: entry.fileType,
                    driveCode: UInt8(ascii: "D"),
                    nmgPayload: entry.fileType == .flw ? nil : payload
                )
            )
        }

        var sequenceFile = makeSequenceFile(entries: sequenceEntries)
        if let sequenceTimingCode {
            sequenceFile = patchSequenceTimingCode(in: sequenceFile, timingCode: sequenceTimingCode)
        }
        debugDump(sequenceFile, filename: "last-send-editor-program-sequence.sys")
        steps.append(try sendSequenceFile(sequenceFile))
        steps.append(try simpleCommand(major: 0x04, minor: 0x02))
        return steps
    }

    public mutating func sendSystemFile(
        name: String,
        content: Data
    ) throws -> [String] {
        [
            try sendChunkedFile(
                name: name,
                content: content,
                command: 0x02,
                descriptorNameLength: 12,
                descriptorTail: [0x00, 0x00]
            )
        ]
    }

    public mutating func deleteFile(path: String) throws -> String {
        var pathData = Data(path.utf8)
        if pathData.last != 0x00 {
            pathData.append(0x00)
        }
        while pathData.count % 4 != 0 {
            pathData.append(0x00)
        }
        let argWords = UInt8(pathData.count / 4)

        let context = "delete \(path)"
        var lastError: Error?
        for attempt in 1...3 {
            var payload = Data()
            payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
            payload.append(contentsOf: le16(nextSequence()))
            payload.append(contentsOf: [0x07, 0x06, argWords, 0x00])
            payload.append(pathData)
            do {
                try requireOK(try transact(payload), context: context)
                return "\(context): OK"
            } catch SigmaError.timeout {
                lastError = SigmaError.timeout
                if attempt < 3 { usleep(500_000) }
            } catch {
                throw error
            }
        }
        throw lastError ?? SigmaError.timeout
    }

    public mutating func pausePlay() throws -> String {
        var payload = Data()
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
        payload.append(contentsOf: le16(nextSequence()))
        payload.append(contentsOf: [0x06, 0x03, 0x00, 0x00])
        let context = "pausePlay 06:03"
        try requireOK(try transact(payload), context: context)
        return "\(context): OK"
    }

    public mutating func clearAll(partition: Character = "D") throws -> [String] {
        // Per JetFileII v2.8.7 sec 3.7: 0x07:0x07/08/09/0A delete all text/string/picture/array
        // files on a partition. Arg = [partition_letter, 0x00, 0x00, 0x00], ArgLen=1.
        let partByte = UInt8(partition.asciiValue ?? UInt8(ascii: "D"))
        let subs: [(UInt8, String)] = [
            (0x07, "delAllText"),
            (0x08, "delAllString"),
            (0x09, "delAllPic"),
            (0x0a, "delAllArrayPic"),
        ]
        var steps: [String] = []
        for (sub, label) in subs {
            let context = "clearAll \(label) 07:\(String(format: "%02X", sub)) part=\(partition)"
            var lastError: Error?
            var ok = false
            for attempt in 1...3 {
                var payload = Data()
                payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
                payload.append(contentsOf: le16(nextSequence()))
                payload.append(contentsOf: [0x07, sub, 0x01, 0x00])
                payload.append(contentsOf: [partByte, 0x00, 0x00, 0x00])
                do {
                    try requireOK(try transact(payload), context: context)
                    ok = true
                    break
                } catch SigmaError.timeout {
                    lastError = SigmaError.timeout
                    if attempt < 3 { usleep(500_000) }
                } catch {
                    lastError = error
                    break
                }
            }
            if !ok {
                steps.append("\(context): \(lastError.map { "\($0)" } ?? "failed")")
            } else {
                steps.append("\(context): OK")
            }
        }
        return steps
    }

    public mutating func listFiles(flag: UInt8 = 1, path: String = "") throws -> (count: UInt16, raw: Data, names: [String]) {
        // 0x07:0x0B DIR. flag: 0=use Arg path, 1=root of default partition,
        // 2=fonts, 3=text, 4=string, 5=picture, 6=array picture.
        var arg = Data()
        if flag == 0 {
            arg.append(Data(path.utf8))
            if arg.last != 0 { arg.append(0x00) }
            while arg.count % 4 != 0 { arg.append(0x00) }
        }
        let argWords = UInt8((arg.count + 3) / 4)

        var payload = Data()
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
        payload.append(contentsOf: le16(nextSequence()))
        payload.append(contentsOf: [0x07, 0x0b, argWords, flag])
        payload.append(arg)

        let context = "listFiles flag=\(flag) path=\(path)"
        let response = try transact(payload)
        try requireOK(response, context: context)

        // Echo header is 16 bytes: SYN+CS+DataLen+Src+Dst+Serial+Major+Sub+ArgLen+Flag.
        // Then 4-byte arg [count_LE16, reserved_LE16] then N bytes of DirectoryEntryStruct (32B each).
        guard response.count >= 20 else { return (0, Data(), []) }
        let count = UInt16(response[16]) | (UInt16(response[17]) << 8)
        let entries = response.subdata(in: 20..<response.count)
        var names: [String] = []
        let entrySize = 32
        var i = 0
        while i + entrySize <= entries.count {
            let nameBytes = entries.subdata(in: i..<(i + 11))
            let trimmed = nameBytes.prefix { $0 != 0 }
            if let s = String(data: Data(trimmed), encoding: .ascii), !s.isEmpty {
                names.append(s)
            }
            i += entrySize
        }
        return (count, entries, names)
    }

    private mutating func sendFile(name: String, content: Data, command: UInt8) throws -> String {
        try sendChunkedFile(
            name: name,
            content: content,
            command: command,
            descriptorNameLength: 14,
            descriptorTail: []
        )
    }

    private mutating func sendChunkedFile(
        name: String,
        content: Data,
        command: UInt8,
        descriptorNameLength: Int,
        descriptorTail: [UInt8],
        maxChunkSize: Int = 768
    ) throws -> String {
        let chunks = content.chunked(maxSize: maxChunkSize)
        let totalPackets = chunks.count
        if totalPackets > 1 {
            let socket = try openUDPSocket()
            defer { close(socket) }
            for (index, chunk) in chunks.enumerated() {
                try sendFileChunk(
                    name: name,
                    totalContentSize: content.count,
                    chunk: chunk,
                    command: command,
                    descriptorNameLength: descriptorNameLength,
                    descriptorTail: descriptorTail,
                    maxChunkSize: maxChunkSize,
                    totalPackets: totalPackets,
                    currentPacket: index + 1,
                    socketFD: socket
                )
            }
        } else {
            for (index, chunk) in chunks.enumerated() {
                try sendFileChunk(
                    name: name,
                    totalContentSize: content.count,
                    chunk: chunk,
                    command: command,
                    descriptorNameLength: descriptorNameLength,
                    descriptorTail: descriptorTail,
                    maxChunkSize: maxChunkSize,
                    totalPackets: totalPackets,
                    currentPacket: index + 1,
                    socketFD: nil
                )
            }
        }

        let context = "send \(printableName(name))"
        if totalPackets == 1 {
            return "\(context): OK"
        }
        return "\(context): OK (\(totalPackets) chunks)"
    }

    private mutating func sendFileChunk(
        name: String,
        totalContentSize: Int,
        chunk: Data,
        command: UInt8,
        descriptorNameLength: Int,
        descriptorTail: [UInt8],
        maxChunkSize: Int,
        totalPackets: Int,
        currentPacket: Int,
        socketFD: Int32?
    ) throws {
        var descriptor = fixedBytes(name, count: 14)
        if descriptorNameLength != 14 {
            descriptor = fixedBytes(name, count: descriptorNameLength)
        }
        descriptor += le32(UInt32(totalContentSize))
        descriptor += le16(UInt16(maxChunkSize))
        descriptor += le16(UInt16(totalPackets))
        descriptor += le16(UInt16(currentPacket))
        descriptor += descriptorTail

        var payload = Data()
        payload.append(contentsOf: le32(UInt32(chunk.count)))
        payload.append(contentsOf: [0x01, 0x01])
        payload.append(contentsOf: le16(nextSequence()))
        payload.append(contentsOf: [0x02, command])
        payload.append(contentsOf: le16(UInt16(descriptor.count / 4)))
        payload.append(contentsOf: descriptor)
        payload.append(chunk)

        let context = "send \(printableName(name)) chunk \(currentPacket)/\(totalPackets)"
        let maxAttempts = 3
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                if let socketFD {
                    try requireOK(try transact(payload, using: socketFD), context: context)
                } else {
                    try requireOK(try transact(payload), context: context)
                }
                return
            } catch {
                lastError = error
                let isTimeout: Bool
                if case SigmaError.timeout = error {
                    isTimeout = true
                } else {
                    isTimeout = false
                }
                if !isTimeout || attempt == maxAttempts {
                    throw error
                }
                // Sign occasionally acks chunk/control packets just after the default timeout.
                // Retry the same idempotent packet.
                usleep(150_000)
            }
        }
        if let lastError {
            throw lastError
        }
    }

    private mutating func sendSequenceFile(_ content: Data) throws -> String {
        try sendChunkedFile(
            name: "SEQUENT.SYS",
            content: content,
            command: 0x02,
            descriptorNameLength: 12,
            descriptorTail: [0x00, 0x00]
        )
    }

    private mutating func commit(path: String, content: Data) throws -> String {
        var body = fixedBytes(path, count: 32)
        body += le32(UInt32(content.count))
        body += le32(UInt32(sigmaX25(content)))

        var payload = Data()
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
        payload.append(contentsOf: le16(nextSequence()))
        payload.append(contentsOf: [0x02, 0x0e])
        payload.append(contentsOf: le16(UInt16(body.count / 4)))
        payload.append(contentsOf: body)

        let context = "commit \(path)"
        try requireOK(try transact(payload), context: context)
        return "\(context): OK"
    }

    private mutating func simpleCommand(major: UInt8, minor: UInt8) throws -> String {
        var payload = Data()
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
        payload.append(contentsOf: le16(nextSequence()))
        payload.append(contentsOf: [major, minor, 0x00, 0x00])

        let context = "command \(String(format: "%02X:%02X", major, minor))"
        try requireOK(try transact(payload), context: context)
        return "\(context): OK"
    }

    private mutating func nextSequence() -> UInt16 {
        defer { sequence &+= 1 }
        return sequence
    }

    /// Low-level RPC. Sends `(major, sub)` with optional param_3 (word-aligned scalar args)
    /// and param_4 (byte-blob payload), returns response body (bytes after the 16-byte header).
    /// Mirrors FUN_1000f590 in czJetFileII.dll.
    public mutating func queryRPC(
        major: UInt8,
        sub: UInt8,
        param3: Data = Data(),
        param4: Data = Data()
    ) throws -> SigmaRPCResponse {
        guard param3.count % 4 == 0 else {
            throw SigmaError.socket("queryRPC param3 length must be a multiple of 4 (got \(param3.count))")
        }
        let words = UInt16(param3.count / 4)
        let seq = nextSequence()

        var payload = Data()
        payload.append(contentsOf: le32(UInt32(param4.count)))
        payload.append(contentsOf: [0x01, 0x01])
        payload.append(contentsOf: le16(seq))
        payload.append(contentsOf: [major, sub])
        payload.append(contentsOf: le16(words))
        payload.append(param3)
        payload.append(param4)

        let response = try transact(payload)
        guard response.count >= 16 else {
            throw SigmaError.shortResponse("rpc \(String(format: "%02X:%02X", major, sub))", hex(response))
        }
        let respMajor = response[12]
        let respSub = response[13]
        let respWords = UInt16(response[14]) | (UInt16(response[15]) << 8)
        let respParam4Len = UInt32(response[4])
            | (UInt32(response[5]) << 8)
            | (UInt32(response[6]) << 16)
            | (UInt32(response[7]) << 24)
        let respSeq = UInt16(response[10]) | (UInt16(response[11]) << 8)

        let body = response.suffix(from: response.startIndex + 16)
        let param3Len = Int(respWords) * 4
        let safeParam3Len = min(param3Len, body.count)
        let param3Out = Data(body.prefix(safeParam3Len))
        let remaining = body.dropFirst(safeParam3Len)
        let param4Len = min(Int(respParam4Len), remaining.count)
        let param4Out = Data(remaining.prefix(param4Len))

        return SigmaRPCResponse(
            major: respMajor,
            sub: respSub,
            sequence: respSeq,
            param3: param3Out,
            param4: param4Out,
            raw: response
        )
    }

    /// czReadPCBID — major=1, sub=0x1b.
    /// Response body layout: u16 status (0x9005) + u32 pcb-id (LE).
    public mutating func readPCBID() throws -> UInt32 {
        let response = try queryRPC(
            major: 0x01,
            sub: 0x1b,
            param3: Data(repeating: 0, count: 4)
        )
        let body = response.bodyBytes
        guard body.count >= 6 else {
            throw SigmaError.shortResponse("readPCBID", hex(response.raw))
        }
        let base = body.startIndex
        let status = UInt16(body[base]) | (UInt16(body[base + 1]) << 8)
        guard status == 0x9005 || status == 0x9000 else {
            throw SigmaError.status("readPCBID", status, hex(response.raw))
        }
        return UInt32(body[base + 2])
            | (UInt32(body[base + 3]) << 8)
            | (UInt32(body[base + 4]) << 16)
            | (UInt32(body[base + 5]) << 24)
    }

    /// czReadBrightInfoExt — major=1, sub=0x16. Returns 8-byte brightness telemetry blob:
    /// [mode, level, ...6 reserved]. Mode bit 0 = auto.
    public mutating func readBrightnessInfo() throws -> SigmaBrightnessInfo {
        let response = try queryRPC(major: 0x01, sub: 0x16)
        let body = response.bodyBytes
        guard body.count >= 2 else {
            throw SigmaError.shortResponse("readBrightnessInfo", hex(response.raw))
        }
        let base = body.startIndex
        return SigmaBrightnessInfo(
            modeFlags: body[base],
            level: body[base + 1],
            raw: Data(body)
        )
    }

    /// czReadLEDTime — major=0x05, sub=0x01. No payload. Response body is 8 BCD
    /// bytes (no status prefix; success implied by the wire-header ack):
    ///   yearLow, yearHigh, month, day, hour, minute, second, weekday raw.
    public mutating func readSignTime() throws -> SigmaSignTime {
        let response = try queryRPC(major: 0x05, sub: 0x01)
        let body = response.bodyBytes
        guard body.count >= 8 else {
            throw SigmaError.shortResponse("readSignTime", hex(response.raw))
        }
        let base = body.startIndex
        func bcd(_ byte: UInt8) -> Int { Int(byte >> 4) * 10 + Int(byte & 0x0F) }
        let yearLow = bcd(body[base])
        let yearHigh = bcd(body[base + 1])
        return SigmaSignTime(
            year: yearHigh * 100 + yearLow,
            month: bcd(body[base + 2]),
            day: bcd(body[base + 3]),
            hour: bcd(body[base + 4]),
            minute: bcd(body[base + 5]),
            second: bcd(body[base + 6]),
            weekday: Int(body[base + 7])
        )
    }

    /// czAjustLEDTimeEx — major=0x05, sub=0x04. 12-byte param3 payload:
    ///   yearLow BCD, yearHigh BCD, month BCD, day BCD,
    ///   hour BCD, minute BCD, second BCD, weekday raw,
    ///   u32 reserved (0).
    /// Sigma treats invalid RTC as a render gate — playback engine refuses
    /// to render until the clock is set, so this should be called once on
    /// connect as part of the init handshake.
    public mutating func setSignTime(_ date: Date = Date()) throws {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday],
            from: date
        )
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day,
            let hour = components.hour,
            let minute = components.minute,
            let second = components.second,
            let weekday = components.weekday
        else {
            throw SigmaError.socket("setSignTime: failed to extract date components")
        }
        func bcd(_ value: Int) -> UInt8 {
            let v = max(0, min(99, value))
            return UInt8((v / 10) << 4 | (v % 10))
        }
        var payload = Data(count: 12)
        payload[0] = bcd(year % 100)
        payload[1] = bcd((year / 100) & 0xFF)
        payload[2] = bcd(month)
        payload[3] = bcd(day)
        payload[4] = bcd(hour)
        payload[5] = bcd(minute)
        payload[6] = bcd(second)
        payload[7] = UInt8(weekday & 0xFF)
        let response = try queryRPC(major: 0x05, sub: 0x04, param3: payload)
        guard response.major == 0x05, response.sub == 0x04 else {
            throw SigmaError.shortResponse("setSignTime", hex(response.raw))
        }
    }

    public mutating func replayCapturedPackets(_ packets: [SigmaReplayPacket]) throws -> [String] {
        guard !packets.isEmpty else { return [] }
        var sockets: [UInt16: Int32] = [:]
        defer {
            for socketFD in sockets.values {
                close(socketFD)
            }
        }

        var steps: [String] = []
        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = port.bigEndian
        let ipResult = host.withCString { cString in
            inet_pton(AF_INET, cString, &remote.sin_addr)
        }
        guard ipResult == 1 else {
            throw SigmaError.socket("inet_pton failed for host \(host)")
        }

        for (index, packet) in packets.enumerated() {
            if packet.delayMilliseconds > 0 {
                usleep(useconds_t(packet.delayMilliseconds * 1_000))
            }
            let socketFD: Int32
            if let existing = sockets[packet.sourcePort] {
                socketFD = existing
            } else {
                let created = try openReplaySocket(sourcePort: packet.sourcePort)
                sockets[packet.sourcePort] = created
                socketFD = created
            }

            let sent = packet.payload.withUnsafeBytes { bytes in
                withUnsafePointer(to: &remote) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                        sendto(socketFD, bytes.baseAddress, packet.payload.count, 0, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent == packet.payload.count else {
                throw SigmaError.socket("replay send failed on port \(packet.sourcePort): \(String(cString: strerror(errno)))")
            }
            steps.append("replay packet \(index + 1)/\(packets.count): src \(packet.sourcePort), \(packet.payload.count) bytes")
        }
        return steps
    }

    private func openReplaySocket(sourcePort: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw SigmaError.socket("replay socket() failed: \(String(cString: strerror(errno)))")
        }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = sourcePort.bigEndian
        local.sin_addr = in_addr(s_addr: INADDR_ANY)

        // Best-effort bind to the captured source port to mirror Editor.
        // If this port is unavailable, continue unbound like the manual replay script.
        _ = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                bind(fd, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return fd
    }

    private func openUDPSocket() throws -> Int32 {
        try openUDPSocket(sourcePort: nil)
    }

    private func openUDPSocket(sourcePort: UInt16?) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw SigmaError.socket("socket() failed: \(String(cString: strerror(errno)))")
        }

        if let sourcePort {
            var reuse: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var local = sockaddr_in()
            local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            local.sin_family = sa_family_t(AF_INET)
            local.sin_port = sourcePort.bigEndian
            local.sin_addr = in_addr(s_addr: INADDR_ANY)
            let bindResult = withUnsafePointer(to: &local) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                    bind(fd, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult != 0 {
                close(fd)
                throw SigmaError.socket("bind(\(sourcePort)) failed: \(String(cString: strerror(errno)))")
            }
        }

        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        var timeoutCopy = timeout
        let setRecv = withUnsafePointer(to: &timeoutCopy) {
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        if setRecv != 0 {
            close(fd)
            throw SigmaError.socket("setsockopt(SO_RCVTIMEO) failed: \(String(cString: strerror(errno)))")
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
            throw SigmaError.socket("inet_pton failed for host \(host)")
        }

        let connectResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                connect(fd, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult != 0 {
            close(fd)
            throw SigmaError.socket("connect() failed: \(String(cString: strerror(errno)))")
        }
        return fd
    }

    private func transact(_ payload: Data, using socketFD: Int32) throws -> Data {
        let frame = makeFrame(payload)
        let sendResult = frame.withUnsafeBytes { bytes in
            send(socketFD, bytes.baseAddress, frame.count, 0)
        }
        guard sendResult == frame.count else {
            throw SigmaError.socket("send() failed: \(String(cString: strerror(errno)))")
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let recvCount = recv(socketFD, &buffer, buffer.count, 0)
        if recvCount > 0 {
            return Data(buffer.prefix(recvCount))
        }
        if recvCount == 0 {
            throw SigmaError.noResponse
        }
        if errno == EAGAIN || errno == EWOULDBLOCK {
            throw SigmaError.timeout
        }
        throw SigmaError.socket("recv() failed: \(String(cString: strerror(errno)))")
    }

    private func transact(_ payload: Data) throws -> Data {
        let frame = makeFrame(payload)
        let endpointPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .udp)
        let semaphore = DispatchSemaphore(value: 0)
        let gate = ResumeGate()
        let result = ResultBox<Data>(.failure(SigmaError.timeout))

        @Sendable func finish(_ value: Result<Data, Error>) {
            guard gate.claim() else { return }
            result.value = value
            connection.cancel()
            semaphore.signal()
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: frame, completion: .contentProcessed { error in
                    if let error {
                        finish(.failure(error))
                        return
                    }
                    connection.receiveMessage { data, _, _, error in
                        if let data, !data.isEmpty {
                            finish(.success(data))
                        } else if let error {
                            finish(.failure(error))
                        } else {
                            finish(.failure(SigmaError.noResponse))
                        }
                    }
                })
            case .failed(let error):
                finish(.failure(error))
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
            finish(.failure(SigmaError.timeout))
        }
        semaphore.wait()
        return try result.value.get()
    }
}

public struct SigmaTextProgramEntry: Sendable {
    public var text: String
    public var font: SigmaFont
    public var color: SigmaColor
    public var options: SigmaTextOptions

    public init(
        text: String,
        font: SigmaFont = .normal7,
        color: SigmaColor = .red,
        options: SigmaTextOptions = .default
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.options = options
    }
}

public struct SigmaRPCResponse: Sendable {
    public let major: UInt8
    public let sub: UInt8
    public let sequence: UInt16
    public let param3: Data
    public let param4: Data
    public let raw: Data

    /// Concatenated body (param3 + param4) — useful when the response packs
    /// status/value bytes into whichever slot fits.
    public var bodyBytes: Data {
        if !param3.isEmpty && !param4.isEmpty { return param3 + param4 }
        return param3.isEmpty ? param4 : param3
    }
}

public struct SigmaSignTime: Sendable, Equatable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let second: Int
    public let weekday: Int

    public init(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        weekday: Int
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.weekday = weekday
    }

    public var description: String {
        String(
            format: "%04d-%02d-%02d %02d:%02d:%02d (wd=%d)",
            year, month, day, hour, minute, second, weekday
        )
    }
}

public struct SigmaBrightnessInfo: Sendable {
    public let modeFlags: UInt8
    public let level: UInt8
    public let raw: Data

    public var isAuto: Bool { modeFlags & 0x01 != 0 }
}

public struct SigmaReplayPacket: Sendable {
    public var delayMilliseconds: Int
    public var sourcePort: UInt16
    public var payload: Data

    public init(delayMilliseconds: Int, sourcePort: UInt16, payload: Data) {
        self.delayMilliseconds = max(0, delayMilliseconds)
        self.sourcePort = sourcePort
        self.payload = payload
    }
}

public struct SigmaBinaryProgramEntry: Sendable {
    public var filename: String
    public var content: Data
    public var fileType: SigmaProgramFileType
    public var payloadLengthOverride: Int?

    public init(
        filename: String,
        content: Data,
        fileType: SigmaProgramFileType = .text,
        payloadLengthOverride: Int? = nil
    ) {
        self.filename = filename
        self.content = content
        self.fileType = fileType
        self.payloadLengthOverride = payloadLengthOverride
    }
}

public struct SigmaTextOptions: Sendable {
    public static let `default` = SigmaTextOptions()

    public var inEffectCode: UInt8
    public var outEffectCode: UInt8
    public var speedCode: UInt8
    public var horizontalAlignCode: UInt8
    public var verticalAligns: Bool
    public var holdSeconds: Int
    public var wrapsText: Bool

    public init(
        inEffectCode: UInt8 = UInt8(ascii: "0"),
        outEffectCode: UInt8 = UInt8(ascii: "0"),
        speedCode: UInt8 = UInt8(ascii: "2"),
        horizontalAlignCode: UInt8 = UInt8(ascii: "0"),
        verticalAligns: Bool = true,
        holdSeconds: Int = 2,
        wrapsText: Bool = true
    ) {
        self.inEffectCode = inEffectCode
        self.outEffectCode = outEffectCode
        self.speedCode = speedCode
        self.horizontalAlignCode = horizontalAlignCode
        self.verticalAligns = verticalAligns
        self.holdSeconds = max(0, min(9999, holdSeconds))
        self.wrapsText = wrapsText
    }
}

public enum SigmaFont: String, CaseIterable, Sendable {
    case tiny3
    case normal5
    case normal7
    case normal14
    case normal15
    case normal16

    var code: UInt8 {
        switch self {
        case .tiny3: return UInt8(ascii: "0")
        case .normal5: return UInt8(ascii: "0")
        case .normal7: return UInt8(ascii: "0")
        case .normal14: return UInt8(ascii: "3")
        case .normal15: return UInt8(ascii: "4")
        case .normal16: return UInt8(ascii: "5")
        }
    }

    var sizeCode: UInt8 {
        switch self {
        case .tiny3: return UInt8(ascii: "2")
        case .normal5: return UInt8(ascii: "0")
        case .normal7: return UInt8(ascii: "1")
        case .normal14: return UInt8(ascii: "1")
        case .normal15: return UInt8(ascii: "1")
        case .normal16: return UInt8(ascii: "1")
        }
    }

    public var maxCharactersPerLine: Int {
        switch self {
        case .tiny3:
            return 26
        case .normal5:
            return 16
        case .normal7:
            return 13
        case .normal14:
            return 5
        case .normal15, .normal16:
            return 4
        }
    }
}

public enum SigmaColor: String, CaseIterable, Sendable {
    case red
    case green
    case orange
    case mixedBands
    case mixedCharacters
    case mixedDiagonalDown
    case mixedDiagonalUp

    var code: UInt8 {
        switch self {
        case .red: return UInt8(ascii: "1")
        case .green: return UInt8(ascii: "2")
        case .orange: return UInt8(ascii: "3")
        case .mixedBands: return UInt8(ascii: "4")
        case .mixedCharacters: return UInt8(ascii: "5")
        case .mixedDiagonalDown: return UInt8(ascii: "6")
        case .mixedDiagonalUp: return UInt8(ascii: "7")
        }
    }
}

public enum SigmaProgramFileType: String, Sendable {
    case text
    case picture
    case flw

    var code: UInt8 {
        switch self {
        case .text: return UInt8(ascii: "T")
        case .picture: return UInt8(ascii: "A")
        case .flw: return UInt8(ascii: "F")
        }
    }
}

private func makeNmg(
    text: String,
    font: SigmaFont,
    color: SigmaColor,
    options: SigmaTextOptions,
    editorFontCompat: Bool
) -> Data {
    let safeText = sanitizeSigmaText(text)
    // Detect time tokens to enable dynamic update mode ('b')
    let hasTimeTokens = safeText.contains("{hour}") || safeText.contains("{minute}") ||
                       safeText.contains("{second}") || safeText.contains("{hhmm24}") ||
                       safeText.contains("{hhmm12}")
    let formattedText = formatText(safeText, font: font, wrapsText: options.wrapsText)
    let rows = formattedText.split(separator: "\r", omittingEmptySubsequences: false).map(String.init)
    let isMultiRow = rows.count > 1
    // Mode selection:
    // 'a' = auto-typeset OFF, text scrolls as one continuous unit (Marquee)
    // 'b' = auto-typeset ON, sign formats text into fitted pages (Fitted)
    // Time tokens ALWAYS require 'b' mode for dynamic updates.
    let useBMode = hasTimeTokens || options.wrapsText
    let autoTypesetCode: UInt8 = useBMode ? UInt8(ascii: "b") : UInt8(ascii: "a")
    // Vendor ALWAYS uses 4-digit hold regardless of mode.
    let hold = String(format: "%04d", options.holdSeconds)
    let renderedText = renderMultiRowBytes(rows: rows, defaultFont: font, options: options, isMultiRow: isMultiRow)

    var header = Data([
        0x01, 0x5a, 0x30, 0x30,
        0x02, 0x41, 0x0f, 0x18, 0x05, 0x31, 0x31, 0x30,
        0x30, 0x31, 0x1b, 0x30, autoTypesetCode
    ])
    // 'b' mode requires initialization bytes 18 01 09; 'a' mode does not.
    if useBMode {
        header.append(contentsOf: [0x18, 0x01, 0x09])
    }
    header.append(contentsOf: [0x08, 0x31, 0x0e, UInt8(ascii: "2")])
    header.append(contentsOf: hold.utf8)
    header.append(contentsOf: [
        0x1f, editorFontCompat ? editorFontSelector(for: font) : nmgFontCode(for: font), 0x1e,
        options.horizontalAlignCode, 0x0a, 0x49, options.inEffectCode, 0x0a, 0x4f, options.outEffectCode, 0x0f,
        options.speedCode, 0x1c, color.code, 0x1d, 0x30, 0x1a, font.sizeCode, 0x07,
        0x30
    ])
    header.append(renderedText)
    header.append(0x0d)
    header.append(0x04)
    header.append(contentsOf: "NoteNmg file version:v3.99".utf8)
    if header.count < 195 {
        header.append(contentsOf: repeatElement(UInt8(ascii: " "), count: 195 - header.count))
    }
    header.append(0x04)
    return header
}

/// Font code for NMG header. Vendor captures show both Normal5 and Normal7 use '0'.
private func nmgFontCode(for font: SigmaFont) -> UInt8 {
    switch font {
    case .normal5, .normal7: return UInt8(ascii: "0")
    default: return font.code
    }
}

private func makeEditorNmg(text: String, font: SigmaFont, color: SigmaColor, options: SigmaTextOptions) -> Data {
    let safeText = sanitizeSigmaText(text)
    let hold = String(format: "%04d", options.holdSeconds)
    let hasTimeTokens = safeText.contains("{hour}") || safeText.contains("{minute}") ||
                        safeText.contains("{second}") || safeText.contains("{hhmm24}") ||
                        safeText.contains("{hhmm12}")
    let autoTypesetCode = hasTimeTokens ? UInt8(ascii: "b") : UInt8(ascii: "a")
    let formattedText = formatText(safeText, font: font, wrapsText: options.wrapsText)
    let renderedText = renderMessageBytes(formattedText)
    let displayLength = UInt16(clamping: editorDisplayLength(formattedText))

    var body = Data([
        0x13, 0x18, 0x05, 0x31, 0x31, 0x30, 0x30, 0x31,
        0x1b, 0x30, autoTypesetCode, 0x08, 0x31, 0x0e, 0x32
    ])
    body.append(contentsOf: hold.utf8)
    body.append(contentsOf: [
        0x1f, editorFontSelector(for: font), 0x1e, options.horizontalAlignCode,
        0x0a, 0x49, options.inEffectCode, 0x0a, 0x4f, options.outEffectCode, 0x0f, options.speedCode,
        0x1c, color.code, 0x1d, 0x30, 0x1a, font.sizeCode, 0x07, 0x30
    ])
    body.append(renderedText)
    body.append(0x0d)
    body.append(0x04)
    body.append(contentsOf: "NoteNmg file version:v3.99".utf8)

    let table = editorPostTextTableTemplate()
    let tableStart = body.count + 17 + 102
    let tableOffset = UInt16(clamping: tableStart - 18)

    var data = Data()
    data.append(contentsOf: [0x4e, 0x47, 0x50, 0x00])
    data.append(contentsOf: le16(7))
    data.append(contentsOf: le16(tableOffset))
    data.append(contentsOf: [0x00, 0x00])
    data.append(contentsOf: le16(displayLength))
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00])
    data.append(body)
    if data.count < tableStart {
        data.append(contentsOf: repeatElement(UInt8(ascii: " "), count: tableStart - data.count))
    }
    data.append(table)
    return data
}

private func editorFontSelector(for font: SigmaFont) -> UInt8 {
    // Editor NMG uses size codes: 0x30='0' for Normal5, 0x31='1' for Normal7
    switch font {
    case .normal5:
        return UInt8(ascii: "0")
    case .normal7:
        return UInt8(ascii: "1")
    default:
        return font.sizeCode
    }
}

private func editorDisplayLength(_ text: String) -> Int {
    var length = 0
    var index = text.startIndex
    while index < text.endIndex {
        if text[index] == "{", let end = text[index...].firstIndex(of: "}") {
            let token = String(text[text.index(after: index)..<end]).lowercased()
            if sigmaMarkup[token] != nil {
                length += tokenDisplayWidth[token] ?? 0
                index = text.index(after: end)
                continue
            }
        }
        length += 1
        index = text.index(after: index)
    }
    return length
}

private func editorPostTextTableTemplate() -> Data {
    let path = Paths.editorNmg.path()
    if let source = try? Data(contentsOf: URL(fileURLWithPath: path)), source.count > 18 {
        let tableStart = Int(UInt16(source[6]) | (UInt16(source[7]) << 8)) + 18
        if tableStart > 0, tableStart < source.count {
            return source[tableStart...]
        }
    }
    return Data(repeating: 0, count: 1024)
}

private func sanitizeSigmaText(_ value: String) -> String {
    let normalized = normalizeSigmaText(value)
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -/:.{}_\n\r!@#$%^&*()_+=?,<>[]'")
    var result = ""
    for character in normalized {
        if allowed.contains(character) {
            result.append(character)
        } else {
            result.append(" ")
        }
    }
    while result.contains("  ") {
        result = result.replacingOccurrences(of: "  ", with: " ")
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizeSigmaText(_ value: String) -> String {
    var normalized = value
    let replacements: [(String, String)] = [
        ("\u{201c}", ""),
        ("\u{201d}", ""),
        ("\u{201e}", ""),
        ("\u{00ab}", ""),
        ("\u{00bb}", ""),
        ("\u{2018}", "'"),
        ("\u{2019}", "'"),
        ("\u{201a}", "'"),
        ("\u{201b}", "'"),
        ("\u{2026}", "..."),
        ("\u{2013}", "-"),
        ("\u{2014}", "-"),
        ("\u{2212}", "-"),
        ("\u{00a3}", "{pound}"),
        ("\u{00a0}", " "),
        (";", ",")
    ]
    for (source, target) in replacements {
        normalized = normalized.replacingOccurrences(of: source, with: target)
    }

    var result = ""
    for scalar in normalized.unicodeScalars {
        switch scalar.value {
        case 10, 13:
            result.unicodeScalars.append(scalar)
        case 32...126:
            result.unicodeScalars.append(scalar)
        default:
            result.append(" ")
        }
    }
    while result.contains("  ") {
        result = result.replacingOccurrences(of: "  ", with: " ")
    }
    return result
}

private func formatText(_ text: String, font: SigmaFont, wrapsText: Bool) -> String {
    // Check for explicit newlines first — if the user provided multiple rows,
    // preserve them regardless of mode. The sign handles layout.
    let hasExplicitNewlines = text.contains("\n") || text.contains("\r")
    if hasExplicitNewlines {
        return text
            .replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if !wrapsText {
        // Single line in Marquee mode — collapse everything to one line
        return text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Fitted mode with a single long line (no explicit newlines):
    // word-wrap to display width so the sign can auto-typeset into pages.
    let maxCharacters = font.maxCharactersPerLine
    let words = text
        .split(separator: " ", omittingEmptySubsequences: true)
        .map(String.init)
    var lines: [String] = []
    var current = ""
    for word in words {
        let displayWidth = messageDisplayWidth(word)
        if current.isEmpty {
            current = clipMessageWord(word, maxWidth: maxCharacters)
        } else if messageDisplayWidth(current) + 1 + displayWidth <= maxCharacters {
            current += " " + word
        } else {
            lines.append(current + " ")
            current = clipMessageWord(word, maxWidth: maxCharacters)
        }
    }
    if !current.isEmpty {
        lines.append(current)
    }
    // No .prefix(7) limit — let the sign paginate however many rows it needs.
    return lines.joined(separator: "\r")
}

private func renderMessageBytes(_ text: String) -> Data {
    var rendered = Data()
    var index = text.startIndex
    while index < text.endIndex {
        if text[index] == "{", let end = text[index...].firstIndex(of: "}") {
            let token = String(text[text.index(after: index)..<end]).lowercased()
            if let bytes = sigmaMarkup[token] {
                rendered.append(contentsOf: bytes)
                index = text.index(after: end)
                continue
            }
        }
        rendered.append(contentsOf: String(text[index]).utf8)
        index = text.index(after: index)
    }
    return rendered
}

private func renderMultiRowBytes(rows: [String], defaultFont: SigmaFont, options: SigmaTextOptions? = nil, isMultiRow: Bool = false) -> Data {
    guard let opts = options else {
        // Fallback: plain rendering with no options context.
        return renderFittedBytes(rows: rows, defaultFont: defaultFont)
    }
    return opts.wrapsText
        ? renderFittedBytes(rows: rows, defaultFont: defaultFont)
        : renderMarqueeBytes(rows: rows, defaultFont: defaultFont)
}

// MARK: - Fitted mode rendering
// Shows all rows simultaneously on one page. Uses plain 0x0d separators
// and 'b' auto-typeset mode so the sign paginates correctly.
private func renderFittedBytes(rows: [String], defaultFont: SigmaFont) -> Data {
    var rendered = Data()
    for (rowIndex, rowText) in rows.enumerated() {
        if rowIndex > 0 {
            rendered.append(0x0d)
        }
        var cleanedRow = stripTrailingMarkupTokens(rowText)
        if rowIndex == 0 {
            cleanedRow = stripLeadingColorToken(cleanedRow)
        }
        cleanedRow = stripLeadingFontToken(cleanedRow)
        rendered.append(renderMessageBytes(cleanedRow))
    }
    return rendered
}

// MARK: - Marquee mode rendering
// Continuous scroll with gaps between rows.
// The Editor v3.99 capture (editor-marquee-continuous-20260506-004922.pcap)
// shows the separator between rows is plain 0x0D — nothing else.
// Verified: 5 rows, all separated by single 0x0d bytes, mode 'a'.
private func renderMarqueeBytes(rows: [String], defaultFont: SigmaFont) -> Data {
    var rendered = Data()
    for (rowIndex, rowText) in rows.enumerated() {
        if rowIndex > 0 {
            // Editor-correct separator: plain CR only.
            rendered.append(0x0d)
        }
        var cleanedRow = stripTrailingMarkupTokens(rowText)
        if rowIndex == 0 {
            cleanedRow = stripLeadingColorToken(cleanedRow)
        }
        cleanedRow = stripLeadingFontToken(cleanedRow)
        rendered.append(renderMessageBytes(cleanedRow))
    }
    return rendered
}

/// Strip trailing zero-width markup tokens (e.g. {red}, {font7}) that have no
/// visible text after them. These are artifacts of canvas serialization.
private func stripTrailingMarkupTokens(_ text: String) -> String {
    var result = text
    while true {
        guard let openIndex = result.lastIndex(of: "{"),
              openIndex == result.startIndex || result[result.index(before: openIndex)] != "\\" else { break }
        let afterOpen = result.index(after: openIndex)
        guard let closeIndex = result[afterOpen...].firstIndex(of: "}") else { break }
        guard closeIndex == result.index(before: result.endIndex) else { break }
        let token = String(result[afterOpen..<closeIndex]).lowercased()
        guard sigmaMarkup[token] != nil else { break }
        result = String(result[..<openIndex])
    }
    return result
}

/// Strip a leading colour token (e.g. {red}, {green}) from the start of a row.
/// The NMG header already sets the global colour, so row 1 does not need an
/// inline token at the very start of the text body.
private func stripLeadingColorToken(_ text: String) -> String {
    guard text.hasPrefix("{"),
          let end = text.firstIndex(of: "}"),
          end != text.endIndex else { return text }
    let token = String(text[text.index(after: text.startIndex)..<end]).lowercased()
    let colorTokens = Set(["red", "green", "orange", "yellow", "bands", "characters", "diagonal_down", "diagonal_up"])
    guard colorTokens.contains(token) else { return text }
    let afterEnd = text.index(after: end)
    return String(text[afterEnd...])
}

private func extractCountdownInfo(_ text: String) -> (month: Int, day: Int, year: Int, hour: Int, minute: Int, second: Int, dir: String, label: String)? {
    guard let start = text.firstIndex(of: "{"),
          let end = text[start...].firstIndex(of: "}") else { return nil }
    let token = String(text[start...end])
    return parseCountdownMarker(token)
}

private func stripCountdownMarker(_ text: String) -> String {
    guard let start = text.firstIndex(of: "{"),
          let end = text[start...].firstIndex(of: "}") else { return text }
    let token = String(text[start...end])
    if parseCountdownMarker(token) != nil {
        let afterEnd = text.index(after: end)
        return String(text[afterEnd...])
    }
    return text
}

private func detectRowFont(_ text: String, defaultFont: SigmaFont) -> SigmaFont {
    // Find the first font token in the row
    var index = text.startIndex
    while index < text.endIndex {
        if text[index] == "{", let end = text[index...].firstIndex(of: "}") {
            let token = String(text[text.index(after: index)..<end]).lowercased()
            if token == "font5" { return .normal5 }
            if token == "font7" { return .normal7 }
        }
        index = text.index(after: index)
    }
    return defaultFont
}

private func stripLeadingFontToken(_ text: String) -> String {
    // Strip only the first font token if it appears at the very beginning
    if text.hasPrefix("{font5}") {
        return String(text.dropFirst(7))
    }
    if text.hasPrefix("{font7}") {
        return String(text.dropFirst(7))
    }
    return text
}

private func messageDisplayWidth(_ text: String) -> Int {
    var width = 0
    var index = text.startIndex
    while index < text.endIndex {
        if text[index] == "{", let end = text[index...].firstIndex(of: "}") {
            let token = String(text[text.index(after: index)..<end]).lowercased()
            if sigmaMarkup[token] != nil {
                width += tokenDisplayWidth[token] ?? 2
                index = text.index(after: end)
                continue
            }
        }
        width += 1
        index = text.index(after: index)
    }
    return width
}

private func clipMessageWord(_ word: String, maxWidth: Int) -> String {
    var result = ""
    var width = 0
    var index = word.startIndex
    while index < word.endIndex && width < maxWidth {
        if word[index] == "{", let end = word[index...].firstIndex(of: "}") {
            let token = String(word[word.index(after: index)..<end]).lowercased()
            if sigmaMarkup[token] != nil {
                let tokenWidth = tokenDisplayWidth[token] ?? 2
                if width + tokenWidth > maxWidth { break }
                result += String(word[index...end])
                width += tokenWidth
                index = word.index(after: end)
                continue
            }
        }
        result.append(word[index])
        width += 1
        index = word.index(after: index)
    }
    return result
}

/// Encode a countdown target date/time into the vendor NMG prefix bytes.
/// Reverse-engineered from Sigma Editor 3.99 wire captures (counter3/4/5.pcap).
///
/// Format: [dateByte, yearByte, byte4, timeByte]
/// - dateByte  = month * 32 + day
/// - yearByte  = 0x5c + 2 * (year - 2026)
/// - byte4     = (minute % 8) * 32 + (second / 2)
/// - timeByte  = hour * 8 + (minute / 10)
private func encodeCountdownPrefix(month: Int, day: Int, year: Int, hour: Int, minute: Int = 0, second: Int = 0) -> [UInt8] {
    let dateByte = UInt8(month * 32 + day)
    let yearByte = UInt8(0x5c + 2 * (year - 2026))
    let byte4 = UInt8((minute % 8) * 32 + (second / 2))
    let timeByte = UInt8(hour * 8 + (minute / 10))
    return [dateByte, yearByte, byte4, timeByte]
}

/// Parse a countdown marker token of the form:
///   {cd:M:D:Y:h:m:s:dir:label}
/// e.g. {cd:6:15:2026:14:30:45:down:Time Remaining}
private func parseCountdownMarker(_ text: String) -> (month: Int, day: Int, year: Int, hour: Int, minute: Int, second: Int, dir: String, label: String)? {
    guard text.hasPrefix("{cd:") && text.hasSuffix("}") else { return nil }
    let inner = String(text.dropFirst(4).dropLast())
    let parts = inner.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count >= 9 else { return nil }
    guard let month = Int(parts[0]),
          let day = Int(parts[1]),
          let year = Int(parts[2]),
          let hour = Int(parts[3]),
          let minute = Int(parts[4]),
          let second = Int(parts[5]) else { return nil }
    let dir = String(parts[6])
    let label = parts[7...].joined(separator: ":")
    return (month, day, year, hour, minute, second, dir, label)
}

private let sigmaMarkup: [String: [UInt8]] = [
    "hour": [0x0b, 0x2c],
    "minute": [0x0b, 0x2d],
    "second": [0x0b, 0x2e],
    "hhmm24": [0x0b, 0x2f],
    "hhmm12": [0x0b, 0x30],
    "date_us": [0x0b, 0x20],
    "date_uk": [0x0b, 0x21],
    "pound": [0xa3],
    "red": [0x1c, UInt8(ascii: "1")],
    "green": [0x1c, UInt8(ascii: "2")],
    "orange": [0x1c, UInt8(ascii: "3")],
    "yellow": [0x1c, UInt8(ascii: "3")],
    "bands": [0x1c, UInt8(ascii: "4")],
    "characters": [0x1c, UInt8(ascii: "5")],
    "diagonal_down": [0x1c, UInt8(ascii: "6")],
    "diagonal_up": [0x1c, UInt8(ascii: "7")],
    "font5": [0x1a, UInt8(ascii: "0")],
    "font7": [0x1a, UInt8(ascii: "1")],
    "blk": [0xdb],
    // Counter/countdown tokens (sign firmware replaces these live)
    "countdown_days": [0x25, UInt8(ascii: "d")],
    "countdown_hours": [0x25, UInt8(ascii: "h")],
    "countdown_minutes": [0x25, UInt8(ascii: "m")],
    "countdown_seconds": [0x25, UInt8(ascii: "s")],
]

private let tokenDisplayWidth: [String: Int] = [
    "hour": 2,
    "minute": 2,
    "second": 2,
    "hhmm24": 5,
    "hhmm12": 8,
    "date_us": 8,
    "date_uk": 8,
    "pound": 1,
    "red": 0,
    "green": 0,
    "orange": 0,
    "yellow": 0,
    "bands": 0,
    "characters": 0,
    "diagonal_down": 0,
    "diagonal_up": 0,
    "font5": 0,
    "font7": 0,
    "blk": 0,
    "countdown_days": 2,
    "countdown_hours": 2,
    "countdown_minutes": 2,
    "countdown_seconds": 2,
]

private struct SigmaSequenceEntry {
    init(filename: String, length: Int, fileType: SigmaProgramFileType, driveCode: UInt8, nmgPayload: Data? = nil) {
        self.filename = filename
        self.length = length
        self.fileType = fileType
        self.driveCode = driveCode
        self.nmgPayload = nmgPayload
    }
    let nmgPayload: Data?
    let filename: String
    let length: Int
    let fileType: SigmaProgramFileType
    let driveCode: UInt8
}

private func makeSequenceFile(
    messageLength: Int,
    filename: String = "temp.Nmg",
    fileType: SigmaProgramFileType = .text,
    driveCode: UInt8 = UInt8(ascii: "D"),
    nmgPayload: Data? = nil
) -> Data {
    makeSequenceFile(
        entries: [SigmaSequenceEntry(filename: filename, length: messageLength, fileType: fileType, driveCode: driveCode, nmgPayload: nmgPayload)]
    )
}

private func makeSequenceFile(entries: [SigmaSequenceEntry]) -> Data {
    precondition(!entries.isEmpty)
    precondition(entries.count <= UInt16.max)

    // Sigma Play writes FLW playlist rows with a different compact 44-byte shape.
    // Using that wire-compatible shape improves movie playback vs. the text/picture template.
    if entries.count == 1, entries[0].fileType == .flw {
        var data = Data([
            0x53, 0x51, 0x04, 0x00, // "SQ" header
            0x01, 0x00, 0x00, 0x00,
            0x44, 0x53, 0x0f, 0x7f, 0x08, 0x20, 0x01, 0x01,
            0x01, 0x01, 0x01, 0x01, 0x08, 0x20, 0x01, 0x01,
            0x23, 0x59, 0x01, 0x01,
            0xff, 0x09, 0x00, 0x00
        ])
        data.append(contentsOf: fixedBytes(entries[0].filename, count: 12))
        return data
    }

    // SQ block layout verified from 5 A-set wire captures (2026-05-06).
    // See analysis/captures/A*-*.notes.md and tasks/sq-block-rewrite-plan.md.
    //
    // Block header (16B): count_LE32 + "SQ\x04\x00" + ver_LE32(=1) + "DT\x0f\x7f"
    // Per entry (28B):    tsA(8) + tsB(8) + slot1_LE16 + slot2_LE16 + filename_8B
    // Total per single-entry SequentList: 16 + 28 = 44B.
    var data = Data()
    data.append(contentsOf: le32(UInt32(entries.count)))
    data.append(contentsOf: [0x53, 0x51, 0x04, 0x00])
    data.append(contentsOf: le32(1))
    data.append(contentsOf: [0x44, 0x54, 0x0f, 0x7f])
    let timestamp = sigmaCreationTimestamp()
    for entry in entries {
        data.append(timestamp)
        data.append(timestamp)
        // slot1: timing/dwell. Vendor Editor v3.99 leaks uninitialised stack
        // memory here (verified: A4-WON ≡ A4-WOFF identical despite content
        // diff; A2-WON = 0x2020 = " ", A2-WOFF = 0x7274 = "tr"). Sign appears
        // to ignore. Emit 0 until knob-test capture clarifies semantics.
        data.append(contentsOf: le16(0))
        // slot2: NMG body length.
        data.append(contentsOf: le16(UInt16(clamping: entry.length)))
        data.append(contentsOf: fixedBytes(entry.filename, count: 8))
    }
    return data
}

/// 8-byte BCD timestamp matching Editor v3.99 SQ-block format:
/// (yrLo, yrHi, mo, hr, 01, 01, 01, 01). Editor only fills first 4 fields;
/// trailing 4 bytes are template defaults (verified across 5 captures).
private func sigmaCreationTimestamp(now: Date = Date()) -> Data {
    let cal = Calendar(identifier: .gregorian)
    let parts = cal.dateComponents([.year, .month, .hour], from: now)
    func bcd(_ value: Int) -> UInt8 {
        let clamped = max(0, min(99, value))
        return UInt8(((clamped / 10) << 4) | (clamped % 10))
    }
    let year = parts.year ?? 2000
    let yrLo = bcd(year % 100)
    let yrHi = bcd(year / 100)
    let mo = bcd(parts.month ?? 1)
    let hr = bcd(parts.hour ?? 0)
    return Data([yrLo, yrHi, mo, hr, 0x01, 0x01, 0x01, 0x01])
}

private func filePlacement(for fileType: SigmaProgramFileType) -> (drive: String, folder: String, driveCode: UInt8) {
    switch fileType {
    case .text:
        return ("D", "T", UInt8(ascii: "D"))
    case .picture:
        return ("D", "T", UInt8(ascii: "D"))
    case .flw:
        return ("F", "F", UInt8(ascii: "F"))
    }
}

private func makeEditorSequenceFile() -> Data {
    let candidates = [
        // Prefer whatever the legacy Editor most recently wrote.
        Paths.editorSequence.path()
        ,
        // Fallback to known-good historical capture from Editor v3.99 image send.
        Paths.capturesDirectory.appendingPathComponent("editor-image-seq-A-20260503-004225/SequentList.tmps").path()
    ]
    for path in candidates {
        if let source = try? Data(contentsOf: URL(fileURLWithPath: path)), !source.isEmpty {
            return source
        }
    }
    return makeSequenceFile(messageLength: 0)
}

private func patchSequenceTimingCode(in sequenceFile: Data, timingCode: UInt8) -> Data {
    var output = sequenceFile
    var i = 0
    while i + 3 < output.count {
        if output[i] == 0x26, output[i + 1] == 0x20, output[i + 2] == 0x05 {
            output[i + 3] = timingCode
        }
        i += 1
    }
    return output
}

private func sequenceEntryLength(for filename: String, in sequenceFile: Data) -> Int? {
    let nameData = Data(filename.utf8)
    guard !nameData.isEmpty else { return nil }
    guard let range = sequenceFile.firstRange(of: nameData) else { return nil }
    let index = range.lowerBound
    guard index >= 2 else { return nil }
    let lo = Int(sequenceFile[index - 2])
    let hi = Int(sequenceFile[index - 1])
    let length = lo | (hi << 8)
    return length > 0 ? length : nil
}

private func makeFrame(_ payload: Data) -> Data {
    let crc = sigmaX25(payload)
    var frame = Data([0x55, 0xa3, UInt8((crc >> 8) & 0xff), UInt8(crc & 0xff)])
    frame.append(payload)
    return frame
}

private func debugDump(_ data: Data, filename: String) {
    let buildDir = Paths.buildDirectory
    let target = buildDir.appendingPathComponent(filename)
    try? FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
    try? data.write(to: target)
}

private func payloadHeaderSummary(_ data: Data) -> String {
    guard !data.isEmpty else { return "empty" }
    let head = data.prefix(16)
    let hexHead = head.map { String(format: "%02X", $0) }.joined(separator: " ")
    if data.count >= 3,
       let ascii = String(data: data.prefix(3), encoding: .ascii),
       ascii == "FLV" {
        return "FLV (\(data.count) bytes), head=\(hexHead)"
    }
    if data.count >= 2,
       data[0] == 0x53,
       data[1] == 0x51 {
        return "SQ sequence-like (\(data.count) bytes), head=\(hexHead)"
    }
    if data.count >= 2,
       data[0] == 0x4E,
       data[1] == 0x47 {
        return "NGP/NMG (\(data.count) bytes), head=\(hexHead)"
    }
    return "unknown (\(data.count) bytes), head=\(hexHead)"
}

private func sequenceHeaderSummary(_ data: Data) -> String {
    guard data.count >= 18 else {
        return "short (\(data.count) bytes)"
    }
    let fileCount = Int(data[4]) | (Int(data[5]) << 8)
    let drive = Character(UnicodeScalar(data[8]))
    let fileType = Character(UnicodeScalar(data[9]))
    let timingA = data.count > 23 ? data[23] : 0
    let timingB = data.count > 31 ? data[31] : 0
    return String(
        format: "SQ entries=%d drive=%C type=%C timingA=0x%02X timingB=0x%02X len=%d",
        fileCount, drive.unicodeScalars.first!.value, fileType.unicodeScalars.first!.value, timingA, timingB, data.count
    )
}

private func requireOK(_ response: Data, context: String) throws {
    guard response.count >= 18 else {
        throw SigmaError.shortResponse(context, hex(response))
    }
    let status = UInt16(response[16]) | (UInt16(response[17]) << 8)
    guard status == 0x9000 else {
        throw SigmaError.status(context, status, hex(response))
    }
}

private func fixedBytes(_ string: String, count: Int) -> [UInt8] {
    var bytes = Array(string.utf8.prefix(count))
    if bytes.count < count {
        bytes.append(contentsOf: repeatElement(0, count: count - bytes.count))
    }
    return bytes
}



private func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

private func printableName(_ name: String) -> String {
    name.replacingOccurrences(of: "\0", with: "\\0")
}

public enum SigmaError: Error, CustomStringConvertible {
    case timeout
    case noResponse
    case socket(String)
    case shortResponse(String, String)
    case status(String, UInt16, String)

    public var description: String {
        switch self {
        case .timeout:
            return "Timed out waiting for the sign"
        case .noResponse:
            return "No response from the sign"
        case .socket(let message):
            return "Socket error: \(message)"
        case .shortResponse(let context, let bytes):
            return "\(context): short response \(bytes)"
        case .status(let context, let status, let bytes):
            if let decoded = sigmaStatusMeaning(status) {
                return "\(context): status 0x\(String(format: "%04X", status)) (\(decoded)); response \(bytes)"
            }
            return "\(context): status 0x\(String(format: "%04X", status)); response \(bytes)"
        }
    }
}

private func sigmaStatusMeaning(_ status: UInt16) -> String? {
    switch status {
    case 0x2102:
        return "No enough disk space"
    case 0x2103:
        return "C drive left space not enough"
    case 0x2104:
        return "D drive left space not enough"
    case 0x2105:
        return "E drive left space not enough"
    case 0x2106:
        return "F drive left space not enough"
    default:
        return nil
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didClaim = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didClaim else { return false }
        didClaim = true
        return true
    }
}

private final class ResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<Value, Error>

    init(_ value: Result<Value, Error>) {
        storage = value
    }

    var value: Result<Value, Error> {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
