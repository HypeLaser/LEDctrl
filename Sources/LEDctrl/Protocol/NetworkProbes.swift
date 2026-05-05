import Foundation
import Network
import AppKit

enum SerialProbe {
    static func probe(path: String, baud: Int, text: String) -> String {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            return "Could not open \(path): \(String(cString: strerror(errno)))"
        }
        defer { close(fd) }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            return "Could not read serial settings: \(String(cString: strerror(errno)))"
        }
        cfmakeraw(&options)
        let speed = speedForBaud(baud)
        cfsetspeed(&options, speed)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            return "Could not set serial settings: \(String(cString: strerror(errno)))"
        }

        let payload = Array((text + "\r\n").utf8)
        let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
        if written < 0 {
            return "Serial write failed: \(String(cString: strerror(errno)))"
        }

        usleep(300_000)
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = read(fd, &buffer, buffer.count)
        if count > 0 {
            let data = Data(buffer.prefix(count))
            return "Serial response: \(formatData(data))"
        }
        return "Serial probe wrote \(written) byte(s); no response within 300 ms."
    }

    private static func speedForBaud(_ baud: Int) -> speed_t {
        switch baud {
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 115200: return speed_t(B115200)
        default: return speed_t(B115200)
        }
    }
}

enum TCPProbe {
    static func probe(host: String, port: UInt16, text: String) async -> (ok: Bool, message: String) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return (false, "Invalid port")
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            let gate = ResumeGate()
            @Sendable func finish(_ result: (Bool, String)) {
                guard gate.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let data = Data((text + "\r\n").utf8)
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            finish((true, "Connected, send failed: \(error.localizedDescription)"))
                            return
                        }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, error in
                            if let data, !data.isEmpty {
                                finish((true, formatData(data)))
                            } else if let error {
                                finish((true, "Connected, receive error: \(error.localizedDescription)"))
                            } else {
                                finish((true, "Connected; no immediate response"))
                            }
                        }
                    })
                case .failed(let error):
                    finish((false, error.localizedDescription))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                finish((false, "Timed out"))
            }
        }
    }
}
