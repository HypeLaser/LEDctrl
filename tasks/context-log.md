# Context Log — LEDctrl Multi-Row Fix Session
**Session:** 6 May 2026, 00:45–03:30 BST
**Goal:** Fix multi-row message sending for Sigma LED sign
**Outcome:** Fitted mode fixed. Marquee mode partially fixed (gaps inconsistent).

## Key Decisions Made

1. **Mode mapping:**
   - Fitted → 'b' mode (auto-typeset ON)
   - Marquee → 'a' mode (auto-typeset OFF)
   - Time tokens → 'b' mode regardless

2. **Row separators:**
   - Fitted → plain `0x0d`
   - Marquee → plain `0x0d` (matches Editor capture)

3. **Effects (from Editor capture):**
   - Fitted → Jump Out (`0x30`)
   - Marquee → Random (`0x2f`) In/Out, align `0x31`

4. **Hold time:** Always 4 digits (`%04d`)

## What Works

- Fitted mode displays all rows simultaneously and paginates correctly
- Marquee mode scrolls continuously with text matching Editor byte-for-byte

## What's Left

- Marquee row gaps: 1→2=100%, 2→3=70%, 3→4=70%, 4→1=200%
- Likely cause: sequence file or control packet timing difference

## Files

- `docs/protocol-reference.md` — canonical protocol docs
- `docs/handover-20260506.md` — session summary
- `tasks/lessons.md` — mistakes and rules for next time
- `tasks/context-log.md` — this file
