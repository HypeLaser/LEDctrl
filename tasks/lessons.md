# Lessons Learned — LEDctrl

## 6 May 2026 — Fitted/Marquee Multi-Row Fix

### What Went Wrong (And Why)

1. **I confused mode selection.** I switched Fitted mode from 'b' to 'a' thinking 'a' was better for simultaneous display. That was wrong — 'b' auto-typeset is what creates pages. 'a' mode has a hard limit and truncates.

2. **I broke Marquee by overcomplicating the row separator.** I replaced the working plain `0x0d` separator with complex `0x0d 0x18 0x03...` sequences that introduced varying gaps. The Editor capture proved Marquee uses plain `0x0d` — I should have trusted that immediately.

3. **I didn't verify against the capture early enough.** Instead of comparing our output to the Editor pcap at every step, I guessed what "should" work. The capture is the spec.

4. **I assumed Marquee needed per-row effects.** The Editor capture shows Random (`0x2f`) for both In and Out. I had hardcoded Move Left (`0x31`). That difference in effects was contributing to the gap inconsistency.

### Rules For Next Time

- **The capture IS the spec.** When a vendor capture exists, diff our output against it before guessing.
- **Don't change working code without a capture proving the new way.** The initial commit's `0x0d 0x0e` separator worked for Marquee. I should have left it alone until I had evidence.
- **Make one change, test, commit.** I made multiple overlapping changes (mode, separator, effects) which made debugging harder.
- **Check ALL bytes, not just the text body.** The remaining Marquee gap issue is probably in the sequence file or control packets, not the NMG payload.

### Technical Notes

- Fitted mode = 'b' + plain `0x0d` + Jump Out effects
- Marquee mode = 'a' + plain `0x0d` + Random effects (per Editor capture)
- `formatText()` must preserve explicit newlines and NOT truncate with `.prefix(7)`
- Hold time is always 4 digits (`%04d`)
