# C9c — Define Time, 24h, Dis Sec OFF, Colon FLASHING

Capture: `C9c-define-24h-noSec-flash-20260506-223344.pcap`
Date: 2026-05-06 22:34 BST
Editor: Define Time, 24h, Dis Sec OFF, Colon Static **unchecked** (flashing)

## Token

```
07 30 [0b 34 2f 80] 0d 04   OPT=0x80 = 1000 0000
```

## Findings — formula refined

Earlier hypothesis "bit1 always-set" disproved. Bit 1 cleared here.

**True formula** (each flag contributes a fixed multi-bit mask):

```
OPT = 0x80
    | (twelveHour ? 0x03 : 0x00)   // bits 0+1
    | (showSec    ? 0x04 : 0x00)   // bit 2
    | (staticCol  ? 0x0a : 0x00)   // bits 1+3
```

Bit 1 ends up being `12h OR static` — implementation detail (likely a derived "alt-render" flag).

## Verification table

| Sample | 12h | Sec | Static | Expected | Actual |
|---|---|---|---|---|---|
| C7  | 0 | 0 | 1 | 0x80 \| 0x0a = 0x8a | 0x8a ✓ |
| C8  | 0 | 1 | 1 | 0x80 \| 0x04 \| 0x0a = 0x8e | 0x8e ✓ |
| C9  | 1 | 0 | 0 | 0x80 \| 0x03 = 0x83 | 0x83 ✓ |
| C9b | 1 | 1 | 0 | 0x80 \| 0x03 \| 0x04 = 0x87 | 0x87 ✓ |
| C9c | 0 | 0 | 0 | 0x80 = 0x80 | 0x80 ✓ |

## Define Time emit spec (final)

```
0x07 0x30 0x0b 0x34 SUB OPT 0x0d 0x04
            └── master ──┘
SUB = 0x2f  (HH:MM 24h fields baseline; reuses preset enum)
OPT = formula above
```

12h+Static is unreachable via dialog (control greyed) — protocol-emittable but editor never produces it. Untested combination for our SigmaClient: skip until needed.

## Pending

- C10 three separate inserts (H + ":" + M + ":" + S literal) → compare against single Define Time SUB=0x2f OPT=0x84 (24h sec).
- Date / Day-of-week probes.
- Countdown / Countup probes.
