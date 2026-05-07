# C20g — Count down × 2.0 (multiplier probe)

Capture: `C20g-countdown-mult2.0-*.pcap`
Date: 2026-05-06 23:10 BST
Editor: same as C20 except Multiply = 2.0.

## Body diff vs C20

```
C20  (mult 1.0): ... a7 5c 00 60  30 30 31 30 31 30 30 30  25 64 ...
C20g (mult 2.0): ... a7 5c 00 60  30 30 32 30 31 30 30 30  25 64 ...
                                        ^^
                                        pos 2: '1'→'2'
```

Single-char delta. Target field unchanged.

## Reinterpretation of "ASCII flag chunk"

Earlier hypothesis (8-char binary bitfield) was wrong. Actual format = **8-char fixed-position field with embedded ASCII numerics**.

### Layout (working theory)

| Pos | C20 | C20f | C20g | Meaning |
|---|---|---|---|---|
| 0 | '0' | '0' | '0' | reserved / pad |
| 1 | '0' | '0' | '0' | reserved / pad |
| **2-3** | **"10"** | **"10"** | **"20"** | **multiplier × 10 (2-digit decimal)** |
| **4** | **'1'** | **'0'** | **'1'** | **direction: 1=down, 0=up** |
| 5 | '0' | '0' | '0' | reserved |
| 6 | '0' | '0' | '0' | reserved |
| 7 | '0' | '0' | '0' | reserved |

Multiplier 1.0 → "10", 2.0 → "20". Confirmed by single-char move.

## Pending confirmations

- **C20h**: multiplier 1.5 → expect "15" at pos 2-3.
- **C20i**: multiplier 0.5 → expect "05" at pos 2-3 (zero-padded?).
- **C20j**: multiplier 9.9 → confirm 2-digit max range.
- **C20k**: multiplier 10+ → see if pos 1 also used (3-digit?).

If pos 2-3 confirmed as decimal-times-10, **multiplier resolution = 0.1**, range = 0.1..9.9 (or 99.9 if pos 1 extends it).

## Implication for SigmaProgram emitter

```swift
struct CountdownFlags {
    let multiplier: Double   // 0.1 .. 9.9 step 0.1
    let countDown: Bool      // true = down, false = up

    var wireBytes: Data {
        let multTimes10 = Int((multiplier * 10).rounded())
        let multStr = String(format: "%02d", multTimes10)
        let dirChar: Character = countDown ? "1" : "0"
        let s = "00\(multStr)\(dirChar)000"  // 8 chars
        return s.data(using: .ascii)!
    }
}
```

## Updated wire spec for countdown token

```
0x18 0x16 0x0a 0x33  <FAT_DATE_LE> <FAT_TIME_LE>  "00<mult2d><dir>000"  <ASCII format string>  0x0d
```

Where `<mult2d>` = `%02d` of (multiplier × 10), `<dir>` = '1' (down) or '0' (up).

## Open

- C20h: format-string-only test (just `%h`) — confirm fields driven solely by format string, no field-selector flag in pos 0,1,5-7.
- C21: multi-row countdown — verify Editor still emits single token for merged fields.
