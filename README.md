# LEDctrl

Native macOS tooling for the Sigma/JetFileII LED sign at `192.168.11.6:9520`.

This folder is the new home for the Swift app and direct sender. It is intentionally separate from the existing `../LEDSign` Python/C++ repo so both codebases can be compared without overwriting each other.

## What Is Here

- `Package.swift`: Swift Package manifest.
- `Sources/SigmaProtocol`: UDP transport, NMG generation, CRC, and sign upload helpers.
- `Sources/LEDPanelRescue`: SwiftUI/AppKit macOS app.
- `Sources/LEDSigmaSend`: command-line sender that is currently the most reliable way to send text.
- `Sources/LEDProbe`: command-line probe for `QS:VER`.
- `Sources/LEDConfigPatch`: command-line CONFIG.SYS IP patch helper from the initial IP migration work.
- `analysis/notes`: early discovery notes.
- `analysis/reverse-engineering`: current decompilation notes, strings, and disassembly excerpts.
- `demo`: small 80x7 pixel mockups used while testing bitmap composition.

## Known Good Commands

```bash
swift run LEDProbe 192.168.11.6 9520 QS:VER
swift run LEDSigmaSend 192.168.11.6 --font normal7 --color green "RESET OK"
swift run LEDSigmaSend 192.168.11.6 --in-id 4 --out-id 1 --speed 2 --hold 2 "SCROLL IN"
swift run LEDSigmaSend 192.168.11.6 --mode marquee --font normal7 --color green --speed 6 --hold 0 "WEATHER TODAY CLOUDY WITH SUNNY SPELLS AND A LIGHT WESTERLY BREEZE"
swift run LEDSigmaSend 192.168.11.6 --in random-mosaic --out radar-scan --font normal7 --color orange "EFFECT TEST"
swift run LEDSigmaSend -- --list-effects
scripts/open-editor-v399.sh
```

The panel should reply to `QS:VER` with IP `192.168.11.6` and version word `0xA512`.

Effect IDs are zero-based against Sigma's effect table: `0` is Random, `1` is Jump out / no obvious movement, `4` is Scroll left. Speed is `0...6`, fast to slow.

For a continuous headline/weather sentence, use `--mode marquee`. This disables the panel's auto-typeset/word-wrap mode and uses move-left in/out so the sign treats the text as one long line instead of separate words.

Oversized NMG uploads now chunk automatically at 768 bytes. A long marquee test uploaded successfully as `send D\0temp.Nmg: OK (2 chunks)` on 2026-05-02. This is the first working bridge toward full-width pixel graphics and animation payloads.

## Native App Features

The Messages tab uses one ruled seven-line canvas, closer to Editor v3.99's page model. Type anywhere in the canvas, select text, then use the colour/style and `5 High` / `7 High` buttons to apply decoded Sigma inline control tokens before sending as a fitted message or marquee. LEDctrl now previews text directly from the vendor bitmap fonts in `../sigma3000_extracted/FONT/Normal7.fnt` and `Normal5.fnt`, including lowercase glyphs and the built-in glyph-cell spacing. The default send path is currently the lightweight and known-good `sendText(...)` path. The experimental Editor-compatible `NGP` sender remains in code for reverse-engineering, but it is not the default live sender. The Headlines tab loads one-headline-per-line `.txt` files, including `../todays-headlines.txt`, and sends each line as Fit, Scroll, or Auto. Auto keeps short lines fitted and scrolls lines longer than the current font can show across the 80x7 display.

Build and publish the native app with:

```bash
./scripts/build-macos-app.sh
rm -rf /Applications/LEDctrl.app
cp -R build/LEDctrl.app /Applications/LEDctrl.app
open -n /Applications/LEDctrl.app
```

The System Set tab now prepares a patched Sigma Play `SysInfoFile` from a captured known-good 80x7 template. The currently mapped fields are:

- Width/height guard at offsets `0x02`/`0x04`, fixed to `80 x 7`.
- Group/unit address at `0x20`/`0x21`.
- IP address at `0x24`.
- Power schedule at `0x34`.
- Half brightness at `0x40`.
- Serial number at `0x55`.
- Display name at `0x6a`.
- Gateway at `0x88`.
- Subnet mask at `0x8c`.

The prepared file is written to `build/prepared-SysInfoFile`. The app includes an explicit `Write SysInfoFile` button, but treat that as a deliberate operation: it can reboot the sign or move it to a new IP. Baud rate, LED Bin, start-up info, daylight saving, display mode, and several Sigma Play options are visible as reference only until they are captured one change at a time.

## Vendor Editor

The correct old editor is `../sigma3000_extracted/Sigma Editor.exe`, not `Editor plus.exe`. Its embedded strings identify it as `v3.99`, `Nmg file version:v3.99`, caption `Editor`, and `Copyright (2003 - 2006)`.

Launch it on this Mac with:

```bash
scripts/open-editor-v399.sh
```

That script uses Whisky's `MessageMaker` bottle and starts the executable from the extracted Sigma folder so it can find its DLLs, fonts, mode tables, and settings. A launcher app can be rebuilt with:

```bash
scripts/build-editor-launcher-app.sh
```

The launcher is installed as `/Applications/Sigma Editor v3.99.app`.

When this Editor opens it defaults to a multi-entry message/program model: each line/entry can be displayed sequentially, so a batch of data can be loaded and then played back-to-back on the sign. Our native app should mirror this as playlist/program support rather than only sending one live text item.

`Insert Text File...` accepts `*.txt` and `*.bin`, but the old Delphi app has an embedded `20480` character limit and the warning `Char must less than 20480,please create a new file!`. Avoid feeding it large logs or modern UTF-8 files while testing; use a small plain ASCII file such as `demo/editor-safe-import.txt`.

## Neighbor Folders

- `../LEDSign`: existing ClaudeCode / upstream-style Python and C++ JetFileII work. This repo is useful for animation/control-code clues. Do not edit it casually; it currently has local modifications.
- `../sigma3000_extracted`: extracted vendor Sigma software and resources.
- `../twittled_v*_extracted`: extracted TwittLED software.

## Current Priority

Build the native app into a friendly graphics/message package: reliable headline/weather playlists first, then richer simulator-backed pixel graphics and animation controls.
