# Sigma / Editor Reverse Engineering Notes

Date: 2026-05-02

For future-session pickup, read `HANDOFF-2026-05-02.md` first. It contains the current hardware state, recovery notes, capture folder index, decoded system-set offsets, speed mapping, palette findings, and current native app caveats.

## Status

The useful target is not just `Sigma Editor.exe` or `Sigma Play.exe`; it is mainly:

- `analysis/extracted/sigma3000/czJetFileII.dll`
- `analysis/extracted/sigma3000/Sigma Editor.exe`
- `analysis/extracted/sigma3000/Sigma Play.exe`

`Sigma Editor.exe` is a native 32-bit Windows GUI program with Delphi/VCL-looking RTTI and strings. `Sigma Play.exe` is also a native 32-bit Windows GUI program, but `rabin2` misidentifies the full file during one quick pass, likely because of its layout/resources. The named exports in `czJetFileII.dll` are the best route because they expose the protocol and file-generation API directly.

The correct vendor editor for hands-on capture is `../sigma3000_extracted/Sigma Editor.exe`, launched through Whisky's `MessageMaker` bottle with `scripts/open-editor-v399.sh`. Do not confuse this with `Editor plus.exe`; that is a different application. `Sigma Editor.exe` contains the strings `v3.99`, `Nmg file version:v3.99`, caption `Editor`, and `Copyright (2003 - 2006)`.

Observed UI behavior: when `Editor` v3.99 opens it automatically switches into a multi-entry editor/program layout. It can hold multiple display entries and then send/play them back-to-back. Treat this as evidence that the sign's normal workflow is playlist/program-based, not just a single live text message.

`Insert Text File...` is present as `InsertTextfile1Click`. The file dialog filter is `Text files (*.txt)|*.TXT|Bin File(*.Bin)|*.Bin|All files(*.*)|*.*`. Nearby embedded strings show a hard `20480` character limit and the warning `Char must less than 20480,please create a new file!`; old Editor builds may appear to hang on large log files or unsupported encodings.

## Generated Artifacts

- `czJetFileII.exports.txt`: full DLL export list.
- `czJetFileII.strings.txt`: strings from the protocol/helper DLL.
- `SigmaEditor.imports.txt`: imports from `Sigma Editor.exe`.
- `SigmaEditor.strings.txt`: strings and Delphi/VCL symbol clues from `Sigma Editor.exe`.
- `czJetFileII.showmsg-showbmp.disasm.txt`: radare2 disassembly for message/image NMG builders.
- `czJetFileII.showmsg-showbmp.pdc.txt`: radare2 pseudo-C for message/image NMG builders.
- `czJetFileII.writefile.disasm.txt`: disassembly for file write wrappers.
- `czJetFileII.core-write.disasm.txt`: disassembly for the chunked core writer.
- `czJetFileII.transport-send.disasm.txt`: disassembly for the packet/header builder used by the core writer.

## Confirmed Protocol Pieces

The sign is at `192.168.11.6:9520`.

UDP transport frames:

- Request prefix: `55 A3`
- Reply prefix: `55 A4`
- Frame CRC: X25-style CRC over payload, init `0xffff`, reflected poly `0x8408`, final complement.
- Good response status: `0x9000` at response payload status offset.

Current native sender uses:

- `04:01` prepare
- `02:04` upload `D\0temp.Nmg`
- `02:0e` commit `D:\T\temp.Nmg`
- `02:02` upload `SEQUENT.SYS`
- `04:02` play

This is enough for text and small bitmap NMG files. As of 2026-05-02 the Swift sender also chunks oversized uploads at 768 bytes using the descriptor fields that were previously hard-coded to `1 of 1`.

The native sender currently writes one temporary NMG plus `SEQUENT.SYS`. To match the vendor editor's multi-entry behavior, we need to learn and implement the multi-file/program form of `SEQUENT.SYS` and upload multiple NMG entries in one send operation.

2026-05-02 update: text wrapping in the native Swift sender now uses the decoded font size. `normal7` wraps at 11 characters instead of the first rough 7-character guess, so messages such as `RESET OK` should stay on one line on the 80-pixel-wide panel. The Swift sender also now defaults to horizontal center (`1E 30`) and non-random in/out effects (`0A 49 30`, `0A 4F 30`).

## Key DLL Exports

High-value exports in `czJetFileII.dll`:

- `_czShowMsgToNmg@28`
- `_czShowBmpToNmg@16`
- `czShowMsg`
- `czShowMsgEx`
- `czShowPic`
- `czShowPicEx`
- `czBmp2Nmg`
- `czWriteSpecFile`
- `czWriteSpecFileEx`
- `czWriteSystemFile`
- `czPLInit`
- `czPLReadFromLED`
- `czPLSendToLED`
- `_czPLAddFile@12`
- `_czPLModifyFile@8`
- `czReplayList`
- `czReplayCurrFile`
- `czPlayPause`
- `czPlayContinue`
- `czPlayNext`
- `czPlayPrevious`
- `czPlayNextFrame`
- `czTickerStart`
- `czTickerStop`
- `czUploadBuffer`
- `czConnectTest`
- `czResetSystem`
- `czReadSystemSet`
- `czReadSystemInfo`
- `czReadBrightInfo`
- `czWriteBrightCtrlBlock`
- `czWriteSpeedLimit`

## NMG Text Format

`_czShowMsgToNmg@28` builds an NMG-like text body starting with:

```text
QZ00SAX
```

Important control bytes confirmed by capture and disassembly:

- `1A` selects font/size.
- `1C` selects colour.
- Colour codes:
  - red: ASCII `1`
  - green: ASCII `2`
  - orange: ASCII `;`
- Size codes confirmed on the physical panel:
  - 5x5: ASCII `0`
  - 6x7: ASCII `1`

The stock generator includes in/out mode controls and speed/time controls around:

- `0A 49 ...` for in effect
- `0A 4F ...` for out effect
- `0E 32 ...` for timing/duration
- `0F ...` for speed

The current Swift generator uses a captured known-good wrapper rather than a complete clean-room reconstruction of every option. The app and CLI can now set in effect, out effect, speed, hold seconds, colour, font, and horizontal centering.

## Animation / Mode Tables

The human-readable effect names live in:

- `analysis/extracted/sigma3000/modeEN.bin`
- `analysis/extracted/sigma3000/speedEN.bin`

`modeEN.bin` contains 49 named effects:

1. Random
2. Jump out
3. Move left
4. Move right
5. Scroll left
6. Scroll right
7. Move up
8. Move down
9. Scroll to L/R
10. Scroll up
11. Scroll down
12. Fold from L/R
13. Fold from U/D
14. Scroll to U/D
15. Shuttle from L/R
16. Shuttle from U/D
17. Peel off L
18. Peel off R
19. Shutter from U/D
20. Shutter from L/R
21. Raindrops
22. Random mosaic
23. Twinkling stars
24. Radar scan
25. Fan out
26. Fan in
27. Spiral R
28. Spiral L
29. To four corners
30. From four corners
31. To four sides
32. From four sides
33. Scroll out from four blocks.
34. Scroll in to four blocks.
35. Move out from four blocks.
36. Move in to four blocks.
37. Scrl from U/left,square.
38. Scrl from U/right,square.
39. Scrl from L/left,square.
40. Scrl from R/right,square.
41. Scrl from U/left,slanting.
42. Scrl from U/right,slanting.
43. Scrl from L/left,slanting.
44. Scrl from L/right,slanting.
45. Move in from U/left corner.
46. Move in from U/right corner.
47. Move in from L/left corner.
48. Move in from L/right corner.
49. Growing up

`speedEN.bin` contains:

1. Very Fast
2. Fast
3. Medium Fast
4. Medium
5. Medium Slow
6. Slow
7. Very Slow

## Scrolling vs Fitted Text

The 2024 Messagemaker Sigma guide describes long scrolling messages as:

- set both In Mode and Out Mode to `Jump out`
- turn off Word Wrap

Physical-panel testing on 2026-05-02 refined this: `Jump out` plus no wrapping still produced separate word entries on this 80x7 sign. A true continuous marquee needs auto-typeset/word-wrap disabled and move-left in/out, matching the older JetFileII headline examples that used `{typesetoff}{moveLeftIn}{moveLeftOut}`.

- `1B 30 61` = auto-typeset off / word-wrap off
- `1B 30 62` = auto-typeset on / word-wrap on
- `0A 49 31` = Move left in
- `0A 4F 31` = Move left out
- `0F 30...36` = speed selection
- `1E 30` = horizontal center for fitted text

`LEDPanelRescue` now exposes this as two modes:

- `Fitted`: wraps text for the 80x7 sign and keeps it centered without scrolling.
- `Marquee`: disables auto-typeset/wrapping and forces Move-left in/out so a headline or weather sentence scrolls as one continuous line.

No decoded vendor field currently looks like an easing-curve or S-curve parameter. The stock firmware appears to offer discrete effect codes plus speed. True eased text movement is likely a custom pixel-animation feature for our app after chunked upload is ported.

## Bitmap / Pixel Mode

Captured Sigma image messages embed a normal BMP inside an NMG wrapper:

- NMG starts with the same `01 5A 30 30 02 41 ...` wrapper as text messages.
- Embedded BMP starts at offset `91`.
- BMP is 16-bit RGB565 with bitfields.
- The working test file was 26x7. The physical sign displayed a generated 26x7 chevron bitmap correctly.

The failed 80x7 attempt returned `0x9013` / "packet size wrong" because the current Swift sender uploads the whole NMG in one packet.

## Chunked Upload Finding

`czJetFileII.dll` contains a chunked writer:

- `czWriteSystemFile` calls internal `0x1001c2e0` with type `2`.
- `czWriteSpecFile` calls internal `0x1001c2e0` with type `8`.
- `czWriteSpecFileEx` calls internal `0x1001c2e0` with type `13`.
- The core writer reads the local file, calculates chunk count from a configured packet size, and loops over chunks.
- The internal packet/header builder is at `0x1000f590`.

Swift implementation update:

- The existing UDP file descriptor already matched the old protocol shape: filename, total file size, packet size, total packet count, current packet.
- The previous sender always wrote packet size `0x0300`, total packets `1`, current packet `1`.
- `SigmaClient` now splits content into 768-byte chunks and sends each chunk with the same total file size, total packet count, and one-based current packet number.
- Regression test: short text still uploads as one packet.
- Oversized test: a long marquee NMG uploaded successfully as `send D\0temp.Nmg: OK (2 chunks)`.

The next confirmation is a full-width 80x7 bitmap NMG. The previous failure returned `0x9013` because it was sent as one packet; with chunking in place, retrying an 80x7 bitmap should tell us whether the BMP wrapper itself is correct.

## App Implementation Targets

Immediate next targets for `LEDPanelRescue`:

1. Retest full-width 80x7 bitmap upload now that chunked NMG upload works.
2. Add proper effect and speed controls using `modeEN.bin` and `speedEN.bin`.
3. Stop doing live animation by rapid repeated uploads. Generate one message/program/playlist and play it.
4. Add bitmap/pixel composer for the 80x7 panel.
5. Fix macOS text input by moving from the current SwiftPM-launched SwiftUI app to a proper Xcode/AppKit app bundle or a more conventional document-style target.
