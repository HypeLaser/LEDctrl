import Foundation
import AppKit

extension NSString {
    var lineRanges: [NSRange] {
        guard length > 0 else { return [NSRange(location: 0, length: 0)] }
        var ranges: [NSRange] = []
        var start = 0
        while start < length {
            let range = lineRange(for: NSRange(location: start, length: 0))
            ranges.append(range)
            let next = range.location + max(range.length, 1)
            if next <= start { break }
            start = next
        }
        return ranges
    }
}

func formatData(_ data: Data) -> String {
    if let text = String(data: data, encoding: .utf8), text.unicodeScalars.allSatisfy({ $0.value >= 32 || $0 == "\r" || $0 == "\n" || $0 == "\t" }) {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

final class ResumeGate: @unchecked Sendable {
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
