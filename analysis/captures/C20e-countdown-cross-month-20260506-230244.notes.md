# C20e — Countdown, target = 1 June 2026 12:00 (cross-month probe)

Capture: `C20e-countdown-cross-month-20260506-230244.pcap`
Date: 2026-05-06 23:03 BST
Editor: same as C20 except target = 1 June 12pm. Editor preview: 25d12h56m18s.

## Body diff vs C20

```
C20  (7 May 12pm):  ... 0a 33 a7 5c 00 60 30 30 31 30 31 30 30 30 ...
C20e (1 June 12pm): ... 0a 33 c1 5c 00 60 30 30 31 30 31 30 30 30 ...
                              ^^
                              a7→c1 (only byte[0] changed)
```

byte[1..3] unchanged. byte[0] +26 (not +25 as expected for 25-day diff). Investigation reveals format below.

## TARGET FIELD = STANDARD MS-DOS / FAT16 TIMESTAMP

Wire = 4 bytes little-endian, DATE word first, TIME word second.

```
byte[0..1] = DATE (16-bit LE)
  bits 0..4   = day (1..31)
  bits 5..8   = month (1..12)
  bits 9..15  = year - 1980 (0..127)

byte[2..3] = TIME (16-bit LE)
  bits 0..4   = sec / 2 (0..29)
  bits 5..10  = min (0..59)
  bits 11..15 = hour (0..23)
```

### Full verification (all 5 countdown captures)

| Capture | Target | DATE = y«9\|m«5\|d | TIME = h«11\|min«5\|(s/2) | Wire bytes |
|---|---|---|---|---|
| C20  | 2026-05-07 12:00:00 | 46«9\|5«5\|7 = 0x5CA7 | 12«11 = 0x6000 | a7 5c 00 60 ✓ |
| C20b | 2026-05-07 13:00:00 | 0x5CA7 | 13«11 = 0x6800 | a7 5c 00 68 ✓ |
| C20c | 2026-05-08 12:00:00 | 46«9\|5«5\|8 = 0x5CA8 | 0x6000 | a8 5c 00 60 ✓ |
| C20d | 2026-05-07 12:30:00 | 0x5CA7 | 12«11\|30«5 = 0x63C0 | a7 5c c0 63 ✓ |
| C20e | 2026-06-01 12:00:00 | 46«9\|6«5\|1 = 0x5CC1 | 0x6000 | c1 5c 00 60 ✓ |

Encoding 100% deterministic. Epoch = 1980, supports years 1980..2107 (year-offset 0..127 in 7 bits).

## Why earlier "21-bit date counter" hypothesis broke

The C20d analysis (single u32 LE = `hour|minute|date_counter`) appeared correct because:
- bits 27..31 happened to equal hour (FAT TIME bits 11..15 land at u32 bits 27..31 with DATE-first wire ordering)
- bits 21..26 happened to equal minute (FAT TIME bits 5..10)
- "date counter" was actually the packed FAT DATE word

The C20e cross-month probe broke the linear-counter hypothesis (+26 instead of +25), which led to FAT-format identification.

## Encode formula (Swift)

```swift
struct DOSTimestamp {
    let year: Int   // 1980..2107
    let month: Int  // 1..12
    let day: Int    // 1..31
    let hour: Int   // 0..23
    let minute: Int // 0..59
    let second: Int // 0..58 (encoded /2, even values only)

    var wireBytes: Data {
        let date = UInt16((year - 1980) << 9) | UInt16(month << 5) | UInt16(day)
        let time = UInt16(hour << 11) | UInt16(minute << 5) | UInt16(second / 2)
        var d = Data()
        d.append(UInt8(date & 0xFF))
        d.append(UInt8((date >> 8) & 0xFF))
        d.append(UInt8(time & 0xFF))
        d.append(UInt8((time >> 8) & 0xFF))
        return d
    }
}
```

## Implication for SigmaProgram emitter

```
Countdown wire token:
  0x18 0x16 0x0a 0x33  <FAT_DATE_LE> <FAT_TIME_LE>  <8 ASCII flags>  <ASCII format string>  0x0d
```

Sub-second resolution unsupported (FAT TIME = sec/2). Editor likely zeros sec field; user-set seconds will be irrelevant for our emit path.

## Open

- C20f: Count down → Count up → diff "00101000" for direction bit.
- C20g: multiplier 1.0 → 2.0 → diff "00101000" for scale field.
- C20h: count down with only `%h` → confirm format string drives field rendering.
