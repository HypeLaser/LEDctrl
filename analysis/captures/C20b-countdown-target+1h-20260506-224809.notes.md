# C20b — Countdown, target shifted +1h (2026-05-07 13:00)

Capture: `C20b-countdown-target+1h-20260506-224809.pcap`
Date: 2026-05-06 22:49 BST
Editor: same as C20 except target = 7 May 1pm
Sign: "014850" (0d 14h 8m 50s — confirms +1hr shift vs C20)

## Body diff vs C20

```
C20  (12pm): ... 0a 33 a7 5c 00 60 30 30 31 30 31 30 30 30 25 64 25 68 25 6d 25 73 ...
C20b (1pm):  ... 0a 33 a7 5c 00 68 30 30 31 30 31 30 30 30 25 64 25 68 25 6d 25 73 ...
                                ^^
                                60 → 68
```

Single-byte delta. All other body bytes byte-identical (excluding NMG body length = 240 vs 243; trailing whitespace count differs slightly, presumably auto-padding).

## Findings

### Target time encoding

- 32-bit BE interpretation: `0x60005CA7 → 0x68005CA7`. Diff = `0x08000000` per +1 hour.
- `0x60 / 8 = 12` and `0x68 / 8 = 13` — **high byte = hour × 8** (no minute encoding tested yet).
- Low 3 bits of high byte likely hold minute-bucket (8 buckets = 7.5 min resolution? Or fewer bits used).
- Lower 24 bits `00 5c a7` constant for target on same date — likely encode date.

### ASCII `00101000` chunk

- Unchanged across C20 / C20b → not the target time.
- Hypothesis: 8-char ASCII bitfield for format options (Count direction, multiplier flags, field selectors).
- Diff probes needed for: Count up vs Count down, multiplier 1.0 vs 2.0, fewer placeholder fields.

### Format string

- `25 64 25 68 25 6d 25 73` = `%d%h%m%s` literal ASCII.
- Sign-side parser substitutes computed counter values.
- Single format string covers all 4 fields user inserted (Editor merged them into one row).

## Open

- C20c: shift target by +1 day → expect lower 24 bits to change, high byte stay at 0x60 (if encoding splits date/time).
- C20d: shift target by +30 minutes → confirm sub-hour encoding (low 3 bits of high byte? or different field?).
- C20e: switch Count down → Count up → diff `00101000` chunk for direction bit.
- C20f: multiply 1.0 → 2.0 → diff `00101000` chunk for scale field.

## Implication for SigmaProgram emitter

Two sub-encoders needed:
1. **Target time → 4-byte field** (formula TBD; needs date+min probe).
2. **Format string assembly** — ASCII printf-style with `%d%h%m%s` placeholders.

Master directive byte = `0x18` (vs `0x0b` clock). Token form:
```
0x18 0x16 0x0a 0x33  <4B target>  <8 ASCII flags>  <ASCII format string>  0x0d
```
