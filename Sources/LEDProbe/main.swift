import Foundation
import Network

let args = CommandLine.arguments
guard args.count >= 4, let portNumber = UInt16(args[2]) else {
    print("Usage: LEDProbe <host> <port> <message>")
    exit(2)
}

let host = args[1]
let port = NWEndpoint.Port(rawValue: portNumber)!
let message = args[3]
let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
let group = DispatchGroup()
group.enter()

@Sendable func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

@Sendable func decodeQSVER(_ data: Data) -> String? {
    let bytes = Array(data)
    guard bytes.count >= 14,
          bytes[0] == 0x51, bytes[1] == 0x53, bytes[2] == 0x3A,
          bytes[7] == 0x41, bytes[8] == 0x44, bytes[9] == 0x3A
    else {
        return nil
    }

    let ip = bytes[(bytes.count - 4)..<bytes.count].reversed().map(String.init).joined(separator: ".")
    let versionWord = UInt16(bytes[4]) << 8 | UInt16(bytes[3])
    return "decoded: QS:VER ip=\(ip) version-word=0x\(String(format: "%04X", versionWord))"
}

connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        let payload = Data((message + "\r\n").utf8)
        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                print("send-error: \(error)")
                connection.cancel()
                group.leave()
                return
            }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                if let data, !data.isEmpty {
                    print("hex: \(hex(data))")
                    if let text = String(data: data, encoding: .utf8) {
                        print("text: \(text)")
                    }
                    if let decoded = decodeQSVER(data) {
                        print(decoded)
                    }
                } else if let error {
                    print("recv-error: \(error)")
                } else {
                    print("no-response")
                }
                connection.cancel()
                group.leave()
            }
        })
    case .failed(let error):
        print("connect-error: \(error)")
        group.leave()
    default:
        break
    }
}

connection.start(queue: .global(qos: .userInitiated))
let timeout = group.wait(timeout: .now() + 3)
if timeout == .timedOut {
    print("timeout")
    connection.cancel()
}
