# C20c — Countdown, target shifted +1 day (2026-05-08 12:00)

Capture: `C20c-countdown-target+1day-20260506-225441.pcap`
Date: 2026-05-06 22:56 BST
Editor: same as C20 except target = 8 May 12pm. User removed Editor's auto-injected blank row 2 manually.

## Body diff vs C20

```
C20  (7 May 12pm): ... 0a 33 a7 5c 00 60 30 30 31 30 31 30 30 30 25 64 ...
C20c (8 May 12pm): ... 0a 33 a8 5c 00 60 30 30 31 30 31 30 30 30 25 64 ...
                            ^^
                            a7 → a8
```

Single-byte delta. `5c 00` and `60` unchanged.

## 4-byte target field — STRUCTURE LOCKED

Combining C20 + C20b + C20c:

| | byte[0] | byte[1] | byte[2] | byte[3] |
|---|---|---|---|---|
| C20  (7 May 12pm) | **a7** | 5c | 00 | **60** |
| C20b (7 May 1pm)  | **a7** | 5c | 00 | **68** |
| C20c (8 May 12pm) | **a8** | 5c | 00 | **60** |
| diff/day  | +1 | 0 | 0 | 0 |
| diff/hour | 0 | 0 | 0 | +8 |

**Two independent fields, separated by 16 bits of zero padding**:

- **byte[0]** = day counter, increments +1 per day.
- **byte[1..2]** = `5c 00` — likely month/year for current date, OR fixed padding (probe needed).
- **byte[3]** = hour × 8. Low 3 bits free → reserved for minute bucket (8 buckets = 7.5 min res).

Or as 24-bit LE: date = `a7 5c 00` = 0x005CA7 = 23719.

### Epoch hypothesis (24-bit LE interp)

If byte[0..2] is days-since-epoch:
- 23719 days back from 2026-05-07 → epoch ≈ 1961-05-29 (odd, unlikely).
- Testing: probe with target on a different month would reveal whether byte[1] changes (= month-low) or stays 0x5c (= weird epoch).

If byte[0] is local day-of-month + offset and byte[1..2] is month/year:
- 7 May → byte[0] = 0xa7 = 167. 8 May → 0xa8 = 168. So byte[0] increments by exactly 1 per day with no rollover yet.
- 167 doesn't equal 7 (day-of-month), 127 (day-of-year), or 7 + month*N for simple N.

**Conclusion**: format known structurally (24-bit date + hour×8), absolute epoch still ambiguous. C20d with cross-month target (e.g. 1 June) would distinguish "day-counter rolling continuously" vs "byte[0]=day-of-month, byte[1..2]=month/year".

## Hour byte recap

- 12:00 → 0x60 (12 × 8)
- 13:00 → 0x68 (13 × 8)
- Low 3 bits = 0. C20d (target +30 min) will reveal sub-hour encoding.

## Open

- C20d: target = 7 May 12:30pm → check low 3 bits of byte[3] OR new minute byte location.
- C20e: target = 1 June 12pm → distinguish epoch interpretation (continuous counter vs day-of-month + month).
- C20f: Count down → Count up → diff direction flag (likely in `00101000` ASCII chunk).
- C20g: multiplier 1.0 → 2.0 → diff scale field.

## Implication for SigmaProgram emitter (refined)

```
0x18 0x16 0x0a 0x33  <date_lo> <date_mid> <date_hi> <hour*8 | min_bucket>  <8 ASCII flags>  <ASCII format string>  0x0d
```

Where `<date_lo/mid/hi>` is 24-bit LE date (formula TBD) and `<hour*8 | min_bucket>` is `(hour * 8) | (minute_bucket & 7)`.
