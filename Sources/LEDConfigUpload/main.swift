import Foundation
import SigmaProtocol

let args = CommandLine.arguments
guard args.count == 3 || args.count == 4 else {
    print("Usage: LEDConfigUpload <host> <CONFIG.SYS> [port]")
    exit(2)
}

let host = args[1]
let url = URL(fileURLWithPath: args[2])
let port = UInt16(args.count == 4 ? args[3] : "9520") ?? 9520

do {
    let content = try Data(contentsOf: url)
    var client = SigmaClient(host: host, port: port)
    let steps = try client.sendSystemFile(name: "CONFIG.SYS", content: content)
    for step in steps {
        print(step)
    }
} catch {
    print("Config upload failed: \(error)")
    exit(1)
}
