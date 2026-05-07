import Foundation
import SigmaProtocol

struct Case {
    let name: String
    let month: Int; let day: Int; let year: Int
    let hour: Int; let minute: Int; let second: Int
    let multiplier: Double
    let countDown: Bool
    let expectedHex: String
}

let cases: [Case] = [
    Case(name: "C20  7 May 2026 12:00 down 1.0",
         month: 5, day: 7, year: 2026, hour: 12, minute: 0, second: 0,
         multiplier: 1.0, countDown: true,
         expectedHex: "a75c0060" + "3030313031303030"),
    Case(name: "C20b 7 May 2026 13:00 down 1.0",
         month: 5, day: 7, year: 2026, hour: 13, minute: 0, second: 0,
         multiplier: 1.0, countDown: true,
         expectedHex: "a75c0068" + "3030313031303030"),
    Case(name: "C20c 8 May 2026 12:00 down 1.0",
         month: 5, day: 8, year: 2026, hour: 12, minute: 0, second: 0,
         multiplier: 1.0, countDown: true,
         expectedHex: "a85c0060" + "3030313031303030"),
    Case(name: "C20d 7 May 2026 12:30 down 1.0",
         month: 5, day: 7, year: 2026, hour: 12, minute: 30, second: 0,
         multiplier: 1.0, countDown: true,
         expectedHex: "a75cc063" + "3030313031303030"),
    Case(name: "C20e 1 Jun 2026 12:00 down 1.0",
         month: 6, day: 1, year: 2026, hour: 12, minute: 0, second: 0,
         multiplier: 1.0, countDown: true,
         expectedHex: "c15c0060" + "3030313031303030"),
    Case(name: "C20f 7 May 2026 12:00 UP   1.0",
         month: 5, day: 7, year: 2026, hour: 12, minute: 0, second: 0,
         multiplier: 1.0, countDown: false,
         expectedHex: "a75c0060" + "3030313030303030"),
    Case(name: "C20g 7 May 2026 12:00 down 2.0",
         month: 5, day: 7, year: 2026, hour: 12, minute: 0, second: 0,
         multiplier: 2.0, countDown: true,
         expectedHex: "a75c0060" + "3030323031303030"),
    Case(name: "C20h 7 May 2026 12:00 down 1.5",
         month: 5, day: 7, year: 2026, hour: 12, minute: 0, second: 0,
         multiplier: 1.5, countDown: true,
         expectedHex: "a75c0060" + "3030313531303030"),
]

var pass = 0
var fail = 0
for c in cases {
    let prefix = encodeCountdownPrefix(month: c.month, day: c.day, year: c.year,
                                        hour: c.hour, minute: c.minute, second: c.second)
    let flags = encodeCountdownFlags(multiplier: c.multiplier, countDown: c.countDown)
    let combined = prefix + flags
    let hex = combined.map { String(format: "%02x", $0) }.joined()
    let ok = (hex == c.expectedHex)
    print("\(ok ? "PASS" : "FAIL") \(c.name)")
    if !ok {
        print("    expected: \(c.expectedHex)")
        print("    actual:   \(hex)")
    }
    if ok { pass += 1 } else { fail += 1 }
}

print("")
print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
