# C20d — Countdown, target shifted +30 min (2026-05-07 12:30)

Capture: `C20d-countdown-target+30min-20260506-225943.pcap`
Date: 2026-05-06 23:01 BST
Editor: same as C20 except target = 7 May 12:30pm.

## Body diff vs C20

```
C20  (12:00): ... 0a 33 a7 5c 00 60 30 30 31 30 31 30 30 30 ...
C20d (12:30): ... 0a 33 a7 5c c0 63 30 30 31 30 31 30 30 30 ...
                           ^^ ^^
                           00→c0, 60→63
```

## TARGET FIELD CRACKED — bit layout locked

4 bytes LE → u32 = `byte[0] | (byte[1]<<8) | (byte[2]<<16) | (byte[3]<<24)`

| | u32 hex | binary (31..0) |
|---|---|---|
| C20  (7 May 12:00) | 0x60005CA7 | `01100 000000 000000010111001010100111` |
| C20b (7 May 13:00) | 0x68005CA7 | `01101 000000 000000010111001010100111` |
| C20c (8 May 12:00) | 0x60005CA8 | `01100 000000 000000010111001010101000` |
| C20d (7 May 12:30) | 0x63C05CA7 | `01100 011110 000000010111001010100111` |

### Locked layout

```
bits 31..27 (5 bits) = hour    (0..31, used 0..23)
bits 26..21 (6 bits) = minute  (0..63, used 0..59)
bits 20..0  (21 bits) = days-since-sign-epoch
```

### Verification

| Sample | hour bits | min bits | date bits | Decoded |
|---|---|---|---|---|
| C20  | 01100=12 | 000000=0 | 23719 | 12:00 ✓ |
| C20b | 01101=13 | 000000=0 | 23719 | 13:00 ✓ |
| C20c | 01100=12 | 000000=0 | 23720 | 12:00 +1day ✓ |
| C20d | 01100=12 | 011110=30 | 23719 | 12:30 ✓ |

### Sign-internal epoch

`23719 days` = 2026-05-07. Working backward: epoch ≈ 1961-05-29 (odd choice). C20e (cross-month probe) will confirm whether counter is continuous (rules out month/year split inside 21-bit field) or rolls.

For emitter: calibrate empirically. Anchor `(2026-05-07, 23719)` then add/subtract Date diffs.

## Encode formula

```swift
func encodeCountdownTarget(date: Date, hour: Int, minute: Int) -> UInt32 {
    let daysFromAnchor = Calendar.current.dateComponents([.day], from: SIGN_EPOCH_2026_05_07, to: date).day!
    let dateField = UInt32(23719 + daysFromAnchor) & 0x1FFFFF
    let minField = UInt32(minute & 0x3F) << 21
    let hourField = UInt32(hour & 0x1F) << 27
    return hourField | minField | dateField
}
// Wire: little-endian
```

## Untouched ASCII chunk

`30 30 31 30 31 30 30 30` = "00101000" — still constant across all 4 captures (C20/b/c/d). Confirmed: NOT time-related. Must encode mode flags (count direction, multiplier, field selectors).

## Open

- C20e: cross-month target (1 June 12pm) — validate continuous-day-counter hypothesis.
- C20f: Count down → Count up — diff "00101000" for direction bit.
- C20g: multiplier 1.0 → 2.0 — diff "00101000" for scale.
- C20h: count down with only `%h` — confirm format string drives field rendering.
