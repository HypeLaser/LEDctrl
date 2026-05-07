# C9 — Define Time, 12h AM/PM, Dis Sec OFF, Colon Static

Capture: `C9-define-12h-noSec-static-20260506-222934.pcap`
Date: 2026-05-06 22:29 BST
Editor: Define Time, 12h AM/PM, Dis Sec OFF
Sign: "10:29PM"

## NMG body diff

```
C7 (24h, noSec):  07 30 [0b 34 2f 8a] 0d 04   OPT=0x8a = 1000 1010
C8 (24h, Sec):    07 30 [0b 34 2f 8e] 0d 04   OPT=0x8e = 1000 1110
C9 (12h, noSec):  07 30 [0b 34 2f 83] 0d 04   OPT=0x83 = 1000 0011
```

C7 vs C9 XOR = 0x09 → bits 0 and 3 both flipped.

## Findings

- **OPT bit 0 (0x01) = 12h AM/PM mode** (set when 12h, clear when 24h).
- **OPT bit 3 (0x08) = colon-static** (set when static, clear when flashing).
- Editor coupling: enabling 12h auto-clears Colon Static — sign-side default for 12h is flashing colon (matches C2 preset HH:MM AM/PM behaviour where colon flashed even though user didn't explicitly set it).
- bit 1 (0x02) and bit 7 (0x80) remain set across all three captures — likely "always-set" magic / Define Time signature bytes. Treat as constant for now.

## OPT bit map (refined)

| Bit | Value | Meaning |
|---|---|---|
| 0 | 0x01 | 12h AM/PM mode |
| 1 | 0x02 | always-set magic (constant) |
| 2 | 0x04 | show seconds |
| 3 | 0x08 | colon static |
| 4..6 | 0x10..0x40 | reserved (zero in all samples) |
| 7 | 0x80 | always-set magic (constant) |

Encoded mask: `bit7=1 | bit1=1 | flags`. Effectively OPT = 0x82 | (12h?0x01:0) | (sec?0x04:0) | (static?0x08:0).

Verify: C7 = 0x82|0x08 = 0x8a ✓, C8 = 0x82|0x08|0x04 = 0x8e ✓, C9 = 0x82|0x01 = 0x83 ✓.

## Pending probes

- C9b: Define Time, 12h, Sec ON → expect OPT = 0x82|0x01|0x04 = 0x87.
- C9c: Define Time, 24h, Sec OFF, Colon **flashing** (uncheck Colon Static) → expect OPT = 0x82 = 0x82.
- C10: Three separate inserts H + ":" + M + ":" + S — body length and token sequence.
- Date / Day-of-week / Countdown / Countup if menu offers them.
