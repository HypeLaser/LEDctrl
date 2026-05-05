import Darwin
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: LEDSerialProbe <path> <baud> [text]")
    exit(2)
}

let path = args[1]
let baud = Int(args[2]) ?? 9600
let text = args.dropFirst(3).joined(separator: " ")

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

if !text.isEmpty {
    let payload = Array((text + "\r\n").utf8)
    let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
    print("Wrote \(written) byte(s)")
}

usleep(750_000)
var buffer = [UInt8](repeating: 0, count: 1024)
let count = read(fd, &buffer, buffer.count)
if count > 0 {
    let data = Data(buffer.prefix(count))
    let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("Read \(count) byte(s): \(hex)")
} else {
    print("No serial response.")
}
