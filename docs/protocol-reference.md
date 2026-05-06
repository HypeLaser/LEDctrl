# Sigma/JetFileII Protocol Reference

> Generated from analysis of Editor v3.99 wire captures and vendor artifacts.
> This document replaces scattered notes with a single canonical reference.
> **Last updated:** 6 May 2026 02:55 BST

## Table of Contents
1. [Message NMG Formats](#message-nmg-formats)
2. [Row Separators](#row-separators)
3. [Auto-Typeset Modes](#auto-typeset-modes)
4. [Sequence File Format](#sequence-file-format)
5. [Font Codes](#font-codes)
6. [Known Working vs Broken Patterns](#known-working-vs-broken-patterns)

---

## Message NMG Formats

The firmware accepts at least two NMG wrapper formats:

### Format A: Lightweight (01 5a 30 30)

Used by: `LEDSigmaSend`, simple text, Fitted mode, Marquee mode

Structure:
```
01 5a 30 30                    -- magic
02 41 0f 18 05 31 31 30 30 31  -- fixed header
1b 30 <auto>                   -- auto-typeset prefix + mode ('a' or 'b')
[18 01 09]                     -- only for 'b' mode
08 31                          -- fixed
0e <hold_type> <hold>          -- hold prefix + type + value
1f <font> 1e <align>           -- font + align
0a 49 <in> 0a 4f <out>         -- in/out effects
0f <speed>                     -- speed
1c <color> 1d 30 1a <size>     -- color, bg, size
07 30                          -- text start marker
<text body>
0d 04 NoteNmg file version:v3.99<padding>04  -- footer
```

**Verified from captures:**
- `editor-fresh-20260502-203651/outgoing-hex.txt` — single text "EDITOR.V3.99"
- `analysis/captures/rich-style-after-20260502-143140/temp.Nmg` — multi-color inline styles
- `editor-marquee-continuous-20260506-004922.pcap` — 5-row continuous marquee, mode 'a'

**Header differences observed:**

| Capture | Auto | Init | Hold | Font | Align | In | Out | Speed | Color |
|---------|------|------|------|------|-------|----|-----|-------|-------|
| editor-fresh | 62 ('b') | 18 01 09 | 0e 32 30 30 30 32 | 1f 33 | 1e 30 | 0a 49 2f | 0a 4f 2f | 0f 32 | 1c 31 |
| rich-style | 61 ('a') | none | 0e 32 30 30 30 32 | 1f 30 | 1e 30 | 0a 49 4b | 0a 4f 2f | 0f 32 | 1c 31 |
| speed-fast | 61 ('a') | none | 0e 32 30 30 30 32 | 1f 30 | 1e 30 | 0a 49 4b | 0a 4f 2f | 0f 32 | 1c 36 |
| editor-marquee | 61 ('a') | none | 0e 32 30 30 30 32 | 1f 30 | 1e 31 | 0a 49 2f | 0a 4f 2f | 0f 32 | 1c 31 |

**Key findings:**
- Font code `33` seen in editor-fresh for Normal7; `30` seen in rich-style and speed captures
- Both may be valid; `33` might be Editor-specific index, `30` might be NMG-specific
- **Hold type is always `32` ('2' = seconds) and hold is ALWAYS 4 digits** — vendor uses 4 digits even for 'b' mode
- 'b' mode ALWAYS includes `18 01 09` init bytes
- 'a' mode NEVER includes init bytes
- `07 30` is the text-start marker in all captures
- **Marquee Editor capture uses:** In=0x2f (Random), Out=0x2f (Random), Align=0x31

### Format B: NGP (4e 47 50 00)

**Status: BROKEN — DO NOT USE.** Previous attempts caused sign to blank or display garbage.

---

## Row Separators

### Fitted mode (simultaneous display)

Uses **plain 0x0D** between rows. All rows appear on screen together.

Verified from: `rich-style-after-20260502-143140/temp.Nmg`

**Implementation:** `renderFittedBytes()` in `SigmaClient.swift`

### Marquee mode (continuous scroll)

The Editor v3.99 capture (`editor-marquee-continuous-20260506-004922.pcap`) shows the separator between rows is **plain 0x0D only** — nothing else.

Editor NMG hex dump of text body:
```
...ROW 1. 0d THIS IS NOW ROW 2... 0d TROW 3 IS... 0d THIS IS ROW 4... 0d ROW 5 IS...
```

**Implementation:** `renderMarqueeBytes()` in `SigmaClient.swift`

**KNOWN ISSUE:** Even though our NMG text body and header now match the Editor capture byte-for-byte for the fields we've identified, the gaps between rows in Marquee mode are still inconsistent:
- Row 1 → 2: ~100%
- Row 2 → 3: ~70%
- Row 3 → 4: ~70%
- Row 4 → 1 (cycle): ~200%

**Hypothesis:** The remaining difference is likely in the **sequence file** or a **timing parameter** we haven't captured. Need to compare the full packet stream (not just NMG payload) between Editor and our app.

---

## Auto-Typeset Modes

| Mode | Code | Init Bytes | Hold Digits | Use Case |
|------|------|------------|-------------|----------|
| 'a' | 0x61 | none | 4 | Marquee (continuous scroll) |
| 'b' | 0x62 | 18 01 09 | 4 | Fitted (simultaneous rows) |

**Time tokens** (`{hour}`, `{minute}`, `{second}`, `{hhmm24}`, `{hhmm12}`) ALWAYS require 'b' mode.

---

## Sequence File Format

### Single-entry sequence (text/picture)

Wire format from `editor-fresh` capture (44 bytes):
```
53 51 04 00                    -- "SQ" header + 04 00
01 00                          -- entry count = 1
00 00                          -- unknown
44 54                          -- drive 'D' + type 'T'
0f 7f                          -- unknown fixed
26 20 05 20                    -- timing/template A
01 01 01 01                    -- flags
26 20 05 20                    -- timing/template B
01 01 01 01                    -- flags
<length: 2 bytes>              -- payload length (little-endian)
<filename: 12 bytes>           -- "temp.Nmg\0\0\0\0"
```

**Critical differences from our old implementation:**
1. The `26 20 05` blocks end with `20` in vendor, not `01`
2. No `f8 00` prefix before length — length is raw 2-byte little-endian
3. Filename is 12 bytes null-padded, followed by 4 null bytes (16 total after length)

---

## Font Codes

### In NMG header (after 1f)

| Font | Code (ASCII) | Seen In |
|------|-------------|---------|
| Normal5 | 0x30 ('0') | rich-style, speed captures |
| Normal7 | 0x30 ('0') or 0x33 ('3') | rich-style ('0'), editor-fresh ('3') |

### In inline size override (after 1a)

| Font | Code (ASCII) | Verified |
|------|-------------|----------|
| Normal5 | 0x30 ('0') | mixed_font_hex.txt |
| Normal7 | 0x31 ('1') | mixed_font_hex.txt |

---

## Known Working vs Broken Patterns

### WORKING ✅

1. **Single-row text, 'a' mode** — reliable, always works
2. **Fitted mode (multi-row, 'b' mode, plain 0d separators)** — shows all rows simultaneously, paginates correctly
3. **Marquee mode (plain 0d separators, Editor-matched effects)** — scrolls continuously but gaps are inconsistent

### BROKEN / NEEDS VERIFICATION 🔴

1. **NGP format** — sign blanks or displays garbage. Do not use.
2. **Marquee multi-row gap consistency** — our NMG text body matches Editor capture exactly, but gaps between rows vary. Need to compare full packet stream to find remaining difference.
3. **Font code `30` vs `33`** — may cause display issues. Need verification.

---

## Next Steps for Research

1. **Capture full packet stream** for Editor v3.99 Marquee multi-row and compare EVERY byte (NMG + sequence + control packets)
2. **Verify sequence file timing bytes** — the `26 20 05 20` blocks may control Marquee scroll speed/gaps
3. **Check if Editor sends different sequence file for Marquee vs Fitted**
4. **Test font code `33` for Normal7** to see if display changes
5. **Verify `editorPostTextTableTemplate()`** for NGP format — currently broken

---

## Code Architecture Notes

### Separate render paths (implemented 6 May 2026)

The code now has completely separate functions for Fitted and Marquee rendering:

- `renderFittedBytes()` — plain `0x0d` separators, no per-row effects
- `renderMarqueeBytes()` — plain `0x0d` separators (matches Editor capture)
- `renderMultiRowBytes()` — dispatches to the correct renderer based on `options.wrapsText`

### formatText() behavior

- **Explicit newlines present** (`\n` or `\r`): preserves rows exactly, no word-wrap, no truncation
- **No newlines, `wrapsText: false` (Marquee)**: collapses to single line
- **No newlines, `wrapsText: true` (Fitted)**: word-wraps to display width

**Critical fix:** Removed `.prefix(7)` truncation that was chopping rows 4+ in Fitted mode.

### optionsForCanvas() behavior

- **Fitted mode**: forces Jump Out (`0x30`) for both In and Out effects
- **Marquee mode**: forces Random (`0x2f`) for both In and Out, align `0x31`
