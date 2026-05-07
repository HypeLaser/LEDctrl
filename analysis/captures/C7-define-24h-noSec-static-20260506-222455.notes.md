# C7 — Define Time, 24h, Dis Sec OFF, Colon Static

Capture: `C7-define-24h-noSec-static-20260506-222455.pcap`
Date: 2026-05-06 22:27 BST
Editor: Define Time dialog, 24-hour, Dis Sec off, Colon Static on
Sign: "22:27" with static colon

## NMG body diff

```
C1 HH:MM 24h preset:    07 30 [0b 2f]            0d 04   (3-byte token, length 178)
C7 Define Time:         07 30 [0b 34 2f 8a]      0d 04   (5-byte token, length 220)
                              ^^ ^^ ^^ ^^
                              |  |  |  +-- options byte 0x8a
                              |  |  +-- sub-format 0x2f (matches HH:MM 24h preset enum)
                              |  +-- master selector 0x34 = Define Time
                              +-- 0x0b clock-token marker
```

NMG length 220 (vs 218 hour-only base). +2 bytes from 4-byte token vs 2-byte token.

## Findings

- **Define Time = 0x34** master selector (vs preset clock = 0x2c..0x30, 0x60).
- **Token grows to 4 bytes** for Define Time: `0b 34 SUB OPT`.
- **SUB byte 0x2f** is reused from preset enum — matches HH:MM 24h. Define Time references the same component table for "what time fields to show".
- **OPT byte 0x8a** — options bitmask. Bits: `1000 1010`.
  - Hypothesis: bit0=12h-mode (off=0), bit1=show-sec, bit2=??, bit3=colon-style, ...
  - Confirm via C8 (Dis Sec ON same other) and C7b (12h same other) sweep.

## Updated enum

| Token form | Bytes | Source |
|---|---|---|
| 3-byte preset | `07 30 0b XX 0d 04` | C1-C6 |
| 5-byte Define Time | `07 30 0b 34 SUB OPT 0d 04` | C7 |

| Master byte | Meaning | Source |
|---|---|---|
| 0x2c..0x30 | Preset Hour/Min/Sec/HH:MM/HH:MM-AMPM | C1, C2, C4, C5, C6 |
| 0x34 | Define Time | C7 |
| 0x60..0x6F | Preset HH:MM TZ idx 0..15 | C3, C3b |

## Pending

- C8: Define Time, 24h, **Dis Sec ON**, Colon Static → expect SUB change to 0x?? (HH:MM:SS variant) OR OPT bit flip (likely OPT — easier protocol design).
- C9: Define Time, **12h AM/PM**, Dis Sec OFF → expect OPT flip on a single bit, SUB likely stays 0x2f or jumps to 0x30.
- Three-separate-inserts test to compare against Define Time HH:MM:SS.
