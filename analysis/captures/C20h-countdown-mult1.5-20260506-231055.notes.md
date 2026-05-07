# C20h — Count down × 1.5 (multiplier resolution probe)

Capture: `C20h-countdown-mult1.5-*.pcap`
Date: 2026-05-06 23:11 BST
Editor: same as C20 except Multiply = 1.5.

## Body diff vs C20

```
C20  (1.0): ... a7 5c 00 60  30 30 31 30 31 30 30 30  25 64 ...
C20g (2.0): ... a7 5c 00 60  30 30 32 30 31 30 30 30  25 64 ...
C20h (1.5): ... a7 5c 00 60  30 30 31 35 31 30 30 30  25 64 ...
                                   ^^^^^
                                   pos 2-3
```

## Multiplier encoding CONFIRMED

| Editor mult | ASCII pos 2-3 | int(m × 10) |
|---|---|---|
| 1.0 | "10" | 10 ✓ |
| 1.5 | "15" | 15 ✓ |
| 2.0 | "20" | 20 ✓ |

Encoding = `String(format: "%02d", Int(round(mult * 10)))`. Resolution = 0.1, working range 0.1..9.9.

## Side note — NMG length 244 (was 243)

Wire grew by 1 byte: extra `0d` row separator before footer:
```
... %d%h%m%s 0d 0f 32 0d 0d 04
                      ^^
                      extra blank row
```
Editor's auto-row-insert quirk; user may have left a blank row 3 in Editor after multi-edit. Not protocol-relevant.

## FINAL countdown ASCII flag layout

```
"00MM D000"  (8 chars)
  ^^^^ ^
  ││││ └── pos 4: '1'=down, '0'=up
  └┴┴┴── pos 0-3: 4-char placeholder; pos 2-3 = mult × 10 zero-padded; pos 0-1 currently always "00"

Reserved/unknown: pos 0, 1, 5, 6, 7
```

## FINAL countdown wire format

```
0x18 0x16 0x0a 0x33
<u16 LE FAT_DATE> <u16 LE FAT_TIME>
"00" "<mult2d>" "<dir>" "000"
"<format_string>"   ; e.g. "%d%h%m%s"
0x0d
```

Where:
- FAT_DATE = `(year-1980)<<9 | month<<5 | day`  (year 1980..2107)
- FAT_TIME = `hour<<11 | minute<<5 | (sec/2)`
- mult2d = `String(format: "%02d", Int((mult * 10).rounded()))`
- dir = '1' (count down) | '0' (count up)
- format_string = ASCII printf-style with `%d`, `%h`, `%m`, `%s` placeholders, plus arbitrary literal text

## Open

- C20i: format string with literal text mixed in (e.g. `"only %d days left"`) → confirm format-string passes through verbatim.
- C20j: format string omitting fields (e.g. just `%h`) → confirm field rendering driven by format string alone, no extra flag in pos 0,1,5,6,7.
- Pos 0,1,5,6,7 still uncategorized — could be brightness, blink, leading-zero suppression, or simply reserved.
