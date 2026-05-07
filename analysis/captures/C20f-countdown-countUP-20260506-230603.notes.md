# C20f — Count UP, target 2026-05-07 12:00 (direction probe)

Capture: `C20f-countdown-countUP-*.pcap`
Date: 2026-05-06 23:08 BST
Editor: same as C20 except mode = **Count up**.
Note: target is in future, sign renders zeros (count-up needs target in past).

## Body diff vs C20

```
C20  (down): ... 0a 33 a7 5c 00 60  30 30 31 30 31 30 30 30  25 64 ...
C20f (up):   ... 0a 33 a7 5c 00 60  30 30 31 30 30 30 30 30  25 64 ...
                                              ^^
                                              pos 4: '1'→'0'
```

Single character delta in ASCII flag string at position 4. Target field, format string unchanged.

## ASCII flag chunk — partial decode

8-char ASCII string immediately after FAT timestamp. Each char `'0'` or `'1'`. Acts as bitfield encoded as text.

| Pos | Down | Up | Meaning |
|---|---|---|---|
| 0 | '0' | '0' | ? |
| 1 | '0' | '0' | ? |
| 2 | '1' | '1' | constant — possibly "use format string" / "DHMS enabled" |
| 3 | '0' | '0' | ? |
| 4 | **'1'** | **'0'** | **Count direction: 1=down, 0=up** |
| 5 | '0' | '0' | ? |
| 6 | '0' | '0' | ? |
| 7 | '0' | '0' | ? |

## Open

- C20g: multiplier 1.0 → 2.0 — likely flips one of pos 0,1,3,5,6,7.
- C20h: only `%h` (no day/min/sec) — confirm format string is sole field selector (pos 2 should stay '1', positions don't change).
- C20i: very-large multiplier or fractional — test pos 0,1 for scale-mode flags.
