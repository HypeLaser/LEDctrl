# Sigma Protocol Findings

## Mixed Font Sizes (Multi-Row Messages)

**Discovery Date:** 5 May 2026
**Source:** Wire capture of Sigma Editor 3.99 sending to sign

### Vendor Format

The vendor software encodes multi-row messages with per-row font overrides:

```
Row 1 text (uses global font)
0x0D 0x0E <row_param> 0x1A <size> Row 2 text
0x0D 0x0E <row_param> 0x1A <size> Row 3 text
```

Where:
- `0x0D 0x0E` = row separator
- `<row_param>` = 5-digit row offset string (e.g. "20000", "20002")
- `0x1A` = inline size override prefix
- `<size>` = font size code (`0x30` = Normal5, `0x31` = Normal7)

### Example Capture

Message: "THIS IS THE SMALL FONT" | "THIS IS THE BIG FONT" | "BACK TO SMALL FONT"

Bytes:
```
...THIS IS THE SMALL FONT
0x0D 0x0E 0x32 0x30 0x30 0x30 0x30 0x1A 0x31 THIS IS THE BIG FONT
0x0D 0x0E 0x32 0x30 0x30 0x30 0x32 0x1A 0x30 BACK TO SMALL FONT
```

### Implementation

Updated `SigmaClient.swift`:
- `renderMultiRowBytes()` splits text by `\r` and inserts proper row separators
- `detectRowFont()` finds the first `{font5}` or `{font7}` token in each row
- `stripLeadingFontToken()` removes the font token from the row text since the override is already emitted

### Status

- [x] Inline font tokens (`{font5}`, `{font7}`) already mapped in `sigmaMarkup`
- [x] Multi-row separator format implemented
- [x] Per-row font detection implemented
- [ ] Needs testing on actual sign hardware

---

## Countdown/Counter Tokens

**Discovery Date:** 5 May 2026
**Source:** Wire captures of Sigma Editor 3.99 (counter.pcap, counter2.pcap, counter3.pcap, counter4.pcap, counter5.pcap)

### Decoded Format

The sign firmware supports self-updating countdown displays. Each row has a prefix that encodes the target date/time:

**First row:**
```
0x0A 0x33 <date_byte> <year_byte> <byte4> <time_byte> <label>00101000%d Day %h Hour %m Minute %s Second
```

**Subsequent rows:**
```
0x0D 0x18 0x30 0x0A 0x33 <date_byte> <year_byte> <byte4> <time_byte> <label>00101000%d Day %h Hour %m Minute %s Second
```

Where:
- `%d`, `%h`, `%m`, `%s` = days, hours, minutes, seconds remaining (sign replaces live)
- `<date_byte>` = `month * 32 + day_of_month`
- `<year_byte>` = `0x5c + 2 * (year - 2026)`
- `<byte4>` = `(minute % 8) * 32 + floor(second / 2)`
- `<time_byte>` = `hour * 8 + floor(minute / 10)`
- `<label>00101000` = label text + direction suffix (`00101000` = down, `00100000` = up)

### Date Encoding Formula

Verified across all captures:

| Date | month | day | Computed | Actual |
|------|-------|-----|----------|--------|
| 14 May 2026 | 5 | 14 | 5*32+14 = 174 = 0xAE | 0xAE ✓ |
| 15 May 2026 | 5 | 15 | 5*32+15 = 175 = 0xAF | 0xAF ✓ |
| 10 Jun 2026 | 6 | 10 | 6*32+10 = 202 = 0xCA | 0xCA ✓ |
| 15 Jun 2026 | 6 | 15 | 6*32+15 = 207 = 0xCF | 0xCF ✓ |
| 1 May 2026 | 5 | 1 | 5*32+1 = 161 = 0xA1 | 0xA1 ✓ |
| 2 May 2026 | 5 | 2 | 5*32+2 = 162 = 0xA2 | 0xA2 ✓ |
| 3 Apr 2025 | 4 | 3 | 4*32+3 = 131 = 0x83 | 0x83 ✓ |

### Year Encoding Formula

| Year | Computed | Actual |
|------|----------|--------|
| 2025 | 0x5c + 2*(-1) = 0x5a | 0x5a ✓ |
| 2026 | 0x5c + 2*(0) = 0x5c | 0x5c ✓ |

### Time Encoding Formula

| Time | hour*8 + min/10 | Computed | Actual |
|------|----------------|----------|--------|
| 09:00:00 | 9*8 + 0 = 72 | 0x48 = 'H' | 'H' ✓ |
| 10:00:00 | 10*8 + 0 = 80 | 0x50 = 'P' | 'P' ✓ |
| 12:15:45 | 12*8 + 1 = 97 | 0x61 = 'a' | 'a' ✓ |
| 16:13:51 | 16*8 + 1 = 129 | 0x81 | 0x81 ✓ |
| 09:30:25 | 9*8 + 3 = 75 | 0x4B = 'K' | 'K' ✓ |
| 14:30:45 | 14*8 + 3 = 115 | 0x73 = 's' | 's' ✓ |

### Byte4 Formula (Minutes + Seconds)

| Time | (min%8)*32 + sec/2 | Computed | Actual |
|------|-------------------|----------|--------|
| 10:30:15 | (6)*32 + 7 = 199 | 0xC7 | 0xC7 ✓ |
| 12:15:45 | (7)*32 + 22 = 246 | 0xF6 | 0xF6 ✓ |
| 16:13:51 | (5)*32 + 25 = 185 | 0xB9 | 0xB9 ✓ |
| 09:30:25 | (6)*32 + 12 = 204 | 0xCC | 0xCC ✓ |
| 14:30:45 | (6)*32 + 22 = 214 | 0xD6 | 0xD6 ✓ |

### Direction Encoding

**Verified via counter5.pcap** (row 1 = count-up, row 2 = count-down, same date/time):
- Both rows use **identical prefix bytes**
- Direction is encoded purely in the label suffix:
  - `00100000` = Count **Up**
  - `00101000` = Count **Down**

### Implementation

Updated `encodeCountdownPrefix()` in `SigmaClient.swift`:
```swift
func encodeCountdownPrefix(month: Int, day: Int, year: Int, hour: Int, minute: Int = 0, second: Int = 0) -> [UInt8]
```

Returns `[dateByte, yearByte, byte4, timeByte]`.

### Status

- [x] Countdown tokens (`%d`, `%h`, `%m`, `%s`) mapped in `sigmaMarkup`
- [x] Date encoding formula fully reverse-engineered
- [x] Year encoding formula reverse-engineered
- [x] Time encoding formula fully reverse-engineered (including minutes/seconds)
- [x] Byte4 formula (minute/second encoding) fully reverse-engineered
- [x] Direction encoding verified (label-based, not prefix-based)
- [x] Implementation updated with correct formulas
- [ ] Needs UI integration for countdown builder

---

## Files Modified

- `Sources/SigmaProtocol/SigmaClient.swift` — `makeNmg()`, `renderMultiRowBytes()`, `encodeCountdownPrefix()`, `sigmaMarkup`
- `Sources/LEDctrl/Utilities/PlexService.swift` — Plex integration (separate feature)

## Capture Files

| File | Description | Key Findings |
|------|-------------|--------------|
| `~/mixed_font.pcap` | 3-row mixed fonts: Normal5, Normal7, Normal5 | Per-row font override bytes (`0x0D 0x0E <offset> 0x1A <size>`) |
| `~/counter.pcap` | Countdown to 15 May 2026 10:00:00 | Countdown prefix format discovered |
| `~/counter2.pcap` | Countdown to 14 May 2026 09:00:00 | Verified date_byte formula |
| `~/counter3.pcap` | 4-row multi-counter (various dates/times) | Verified year_byte, byte4, time_byte formulas |
| `~/counter4.pcap` | 3-row: count-up + 2× count-down (various times) | Count-up uses identical prefix; direction in label suffix |
| `~/counter5.pcap` | 2-row: count-up vs count-down (same date/time) | Confirmed direction encoding: `00100000`=up, `00101000`=down |
| `~/counter6.pcap` | 3-row: GMT+1 time, seconds only, 24h static colon | `'b'` mode required for real-time updates; `18 01 09` init bytes; hold=`000` for continuous; font code `0x30` for Normal7 |

## Multi-File vs Single-File Sending

**Critical finding from counter6.pcap and mixed_font.pcap:**

The vendor Editor sends **each row as a separate NMG file** (ROW001.Nmg, ROW002.Nmg, etc.) with a SEQUENCE.SYS file controlling playback order. This is required for:
- Per-row font settings to be honored
- Proper hold/pause times between rows
- Fitted mode to show each row as a separate message

**Our old behavior:** Sent all rows as a single NMG with `\r` separators. This caused:
- Fitted mode: Only showed row 1
- Marquee mode: All rows scrolled continuously with no pause
- Font overrides: Ignored — all rows used row 1's font

**Fix:** Switched `sendCurrentMessage()` to use `sendTextProgram()` for multi-row messages, sending each row as a separate file with per-row font detection.

## Real-Time Clock Mode ('b' mode)

**Discovery from counter6.pcap:**
- Messages with time tokens (`{hour}`, `{minute}`, `{second}`, `{hhmm24}`, `{hhmm12}`) must use `'b'` auto-typeset mode
- `'b'` mode requires extra init bytes: `0x18 0x01 0x09`
- `'b'` mode enables the sign firmware to refresh time tokens continuously
- Hold time is `000` (3 digits) for continuous cycling
- Font code for Normal7 is `0x30` (not `0x31`)

## NMG Header Format (Stable Path)

```
01 5a 30 30                    -- header prefix
02 41 0f 18 05 31 31 30 30 31  -- settings
1b 30 <auto>                   -- auto-typeset prefix + mode
[18 01 09]                     -- 'b' mode only: dynamic init bytes
08 31                          -- unknown fixed bytes
0e <speed>                     -- speed prefix + code
<hold>                         -- 3-digit hold ("000" for continuous, "002" for 2s)
32                             -- required marker byte after hold
1f <font>                      -- font prefix + code (Normal7='0', Normal5='9')
1e <align>                     -- align prefix + code
0a 49 <in> 0a 4f <out> 0f     -- in/out effects
<speed> 1c <color> 1d 30 1a <size> 07 30  -- style + size
<text content>
0d 04 NoteNmg file version:v3.99<padding>04  -- footer
```

## Next Steps

1. ✅ Test mixed-font multi-row messages on actual sign hardware
2. ✅ Test countdown messages on sign
3. ✅ Decode time_byte formula for non-zero minutes/seconds
4. ✅ Build UI countdown builder
5. ✅ Fix multi-file sending for per-row fonts and holds
6. ✅ Fix real-time seconds mode ('b' mode with init bytes)
