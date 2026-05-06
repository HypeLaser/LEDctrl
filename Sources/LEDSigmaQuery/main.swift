import Foundation
import SigmaProtocol

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("""
    Usage: LEDSigmaQuery <host> <command> [args...]
      Commands:
        pcbid                          czReadPCBID  (major=0x01 sub=0x1B)
        brightness                     czReadBrightInfoExt (major=0x01 sub=0x16)
        time                           czReadLEDTime (major=0x05 sub=0x01)
        settime [now|YYYY-MM-DD-HH:MM:SS]  czAjustLEDTimeEx (major=0x05 sub=0x04)
        rpc <major-hex> <sub-hex> [param3-hex] [param4-hex]
                                       Raw RPC, hex strings (e.g. "01" "1b" "00000000" "")
    """.utf8))
    exit(2)
}

let host = args[1]
let cmd = args[2].lowercased()
var client = SigmaClient(host: host)

func hexDump(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func parseHex(_ string: String) -> Data? {
    let cleaned = string.filter { !$0.isWhitespace }
    guard cleaned.count % 2 == 0 else { return nil }
    var data = Data()
    var index = cleaned.startIndex
    while index < cleaned.endIndex {
        let next = cleaned.index(index, offsetBy: 2)
        guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
        data.append(byte)
        index = next
    }
    return data
}

do {
    switch cmd {
    case "pcbid":
        let id = try client.readPCBID()
        print("pcbid: 0x\(String(format: "%08X", id))  (\(id))")

    case "brightness":
        let info = try client.readBrightnessInfo()
        print("brightness: mode=0x\(String(format: "%02X", info.modeFlags)) (\(info.isAuto ? "auto" : "manual")) level=\(info.level) raw=\(hexDump(info.raw))")

    case "time":
        let t = try client.readSignTime()
        print("time: \(t.description)")

    case "settime":
        let date: Date
        if args.count > 3 && args[3].lowercased() != "now" {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
            guard let parsed = formatter.date(from: args[3]) else {
                FileHandle.standardError.write(Data("settime: bad date \(args[3])\n".utf8))
                exit(2)
            }
            date = parsed
        } else {
            date = Date()
        }
        try client.setSignTime(date)
        print("settime: ok (\(date))")

    case "rpc":
        guard args.count >= 5,
              let majorByte = UInt8(args[3], radix: 16),
              let subByte = UInt8(args[4], radix: 16) else {
            FileHandle.standardError.write(Data("rpc requires <major-hex> <sub-hex>\n".utf8))
            exit(2)
        }
        let p3 = args.count > 5 ? (parseHex(args[5]) ?? Data()) : Data()
        let p4 = args.count > 6 ? (parseHex(args[6]) ?? Data()) : Data()
        let resp = try client.queryRPC(major: majorByte, sub: subByte, param3: p3, param4: p4)
        print("response major=0x\(String(format: "%02X", resp.major)) sub=0x\(String(format: "%02X", resp.sub)) seq=0x\(String(format: "%04X", resp.sequence))")
        print("param3 (\(resp.param3.count)B): \(hexDump(resp.param3))")
        print("param4 (\(resp.param4.count)B): \(hexDump(resp.param4))")
        print("raw    (\(resp.raw.count)B): \(hexDump(resp.raw))")

    default:
        FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
