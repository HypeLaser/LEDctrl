# C3 — preset HH:MM(TimeZone) GMT

Capture: `C3-preset-hhmm-tz-gmt-20260506-220429.pcap`
Date: 2026-05-06 22:04 BST
Wall-clock at send: 22:04
Editor display: " 9:04PM" (leading space, 12h, GMT = BST-1)
Sign rendered: same form (per user)

## Editor input

Identical to C1/C2 except clock preset: **HH:MM(TimeZone)** with TZ dropdown set to **GMT**.
Editor auto-rendered as 12-hour AM/PM format with leading space pad.

## NMG body diff

```
C1: ... 07 30 0b 2f 0d 04 ...    HH:MM 24h
C2: ... 07 30 0b 30 0d 04 ...    HH:MM AM/PM
C3: ... 07 30 0b 60 0d 04 ...    HH:MM TZ-GMT
                ^^
                +-- format byte jumps 0x30 → 0x60
```

NMG length still 178. Body identical except format byte.

## Findings

- **Format byte is a wide enum**, not strictly sequential.
  - `0x2f` HH:MM 24h
  - `0x30` HH:MM AM/PM
  - `0x60` HH:MM TZ-GMT
- Big gap (0x30 → 0x60) implies category bitfield / reserved ranges.
- TZ offset is **NOT** carried in NMG body (length unchanged). Either:
  - Baked into format byte (each TZ a unique value, e.g. 0x60..0x6F = different zones)
  - Stored as sign-side persistent setting
- Hypothesis: bits 0x60 = TZ-mode bit, low nibble = TZ index. Capture C3b (different TZ) needed to discriminate.

## Updated enum table

| Byte | Preset | Source |
|---|---|---|
| 0x2f | HH:MM 24h | C1 |
| 0x30 | HH:MM AM/PM | C2 |
| 0x60 | HH:MM TZ-GMT | C3 |

## Pending probes

- **C3b** — same preset, different TZ (e.g. EST or UTC+5) → does byte change to 0x61/0x62, or stay 0x60 with side data?
- Hour-only / Min-only / Sec-only presets → likely fill 0x31..0x33 region
- Define Time variants → likely separate range (0x40..? or 0x50..?)
