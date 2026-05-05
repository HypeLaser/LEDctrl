import Foundation

enum MediaConverter {
    static func resolveFFmpegPath() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "ffmpeg"
        ]
        for path in candidates {
            if path == "ffmpeg" || FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw AppError.message("ffmpeg not found")
    }

    static func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw AppError.message("Process failed (\(process.terminationStatus)): \(output)")
        }
        return output
    }

    static func summarizeProcessOutput(_ output: String, maxLines: Int = 8) -> [String] {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        if lines.count <= maxLines { return lines }
        return Array(lines.suffix(maxLines))
    }
}
