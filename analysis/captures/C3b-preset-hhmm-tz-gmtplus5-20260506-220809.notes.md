# C3b — preset HH:MM(TimeZone) GMT+5

Capture: `C3b-preset-hhmm-tz-gmtplus5-20260506-220809.pcap`
Date: 2026-05-06 22:08 BST
Wall-clock at send: 22:08
Editor display: " 2:08AM" (12h, leading space, calculated as GMT+5)
Sign rendered: **"04:08PM"** — disagrees with editor by ~14h

## NMG body diff

```
C3  (GMT)   ... 07 30 0b 60 0d 04 ...
C3b (GMT+5) ... 07 30 0b 65 0d 04 ...
                      ^^
                      +-- low nibble = TZ index, 0x60 + 5 = 0x65
```

NMG length unchanged (178). Single-byte delta.

## Findings

- **TZ encoded in low nibble of format byte**: range `0x60..0x6F` covers up to 16 timezones.
- 16-byte enum keeps NMG body length flat regardless of TZ — clever wire economy.
- **Sign rendered 04:08PM vs editor's 02:08AM (~14h delta)** — explained: sign's
  own TZ setting is currently **GMT-12** (lost during earlier factory reset).
  Sign computes: internal-clock - own-TZ + format-TZ = 22:08 - (-12) + 5 = 39:08 mod 24 = 15:08 ≈ 04:08PM.
  Off-by-1 likely DST/table quirk.
  **Conclusion**: format byte is a true offset index, sign just had wrong base TZ.
- Protocol-level: we emit `0b 6X` for X∈[0..F] = 16 timezones. Sign applies signed offset using its own
  TZ-home setting as reference. Caller must ensure sign's home TZ is correct.

## Updated enum table

| Byte | Preset | Source |
|---|---|---|
| 0x2f | HH:MM 24h | C1 |
| 0x30 | HH:MM AM/PM | C2 |
| 0x60 | HH:MM TZ-idx-0 (editor "GMT") | C3 |
| 0x65 | HH:MM TZ-idx-5 (editor "GMT+5", sign disagrees) | C3b |

## Pending probes

- Optional: C3c sweep of TZ indices 1..F to map sign's TZ table empirically (16-byte alphabet).
- More valuable next: Hour-only / Min-only / Sec-only presets, then Define Time variants.

## Action item

When porting clock support to SigmaClient/SigmaProgram, **expose TZ as raw index 0..F** rather than computed offset. Document that sign-side TZ table mapping is firmware-specific and may diverge from vendor editor. Optionally emit a warning if user picks TZ-index in clock-with-TZ preset on a sign whose timezone has not been calibrated.
