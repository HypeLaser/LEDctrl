# Sigma3000 / TwittLED Findings

## Extracted software

- `Sigma3000 Ver4.9.59(EN)-20170310.msi` extracted cleanly into `analysis/extracted/sigma3000`.
- `TwittLED setup.exe` is an Inno Setup 5.4.2 installer and extracted into `analysis/extracted/twittled`.

## Hardware seen by macOS

- Likely panel USB serial device: `/dev/cu.usbmodem11401`.
- USB VID/PID from IORegistry: `0x03eb:0x6119`, shown as `Generic CDC`.
- Other USB device of interest: VID/PID `0x1a86:0x8091`.
- Wired USB Ethernet adapter exists as `en7`, but it was inactive during inspection.
- Panel boot screen reports IP `192.168.0.19`.
- Local LAN is `192.168.11.0/24` via gateway `192.168.11.1`, so `192.168.0.19` is off-subnet and will not be discoverable normally.
- Panel boot screen reports width `80`, height `7`, `B1 9600`, `B2 9600`, power on/off disabled, `LED BIN-A`, version `A512GGUU 0101`.

## Sigma defaults found

- Network mode is enabled by default in several config files.
- Default IP values include `192.168.0.19`, `169.254.10.49`, `169.254.15.30`, `169.254.11.65`, `169.254.18.55`, and `169.254.18.123`.
- Default TCP port is `9520`.
- Custom port is `6410`.
- Serial defaults include `COM1`, `COM9`, `9600`, `19200`, and `115200`.
- The old executable contains strings for `QS:VER`, `QSTECH`, and `QSSIGMA`.
- Old source path strings include `uBaseCMD.pas`, `uGroupNetC.pas`, `uJetFileIICMD.pas`, `uMain.pas`, and `uDNSToIP.pas`.

## Current app scaffold

The new SwiftUI app is `LEDPanelRescue`. It can:

- Enumerate `/dev/cu.*` serial ports.
- Probe selected serial devices with a configurable baud rate and text command.
- Probe Sigma candidate IP/port combinations over TCP.
- Log responses as text or hex.

The command-line helper `LEDProbe` captures exact TCP response bytes:

```bash
swift run LEDProbe 192.168.0.19 9520 QS:VER
```

Observed response from both ports `9520` and `6410`:

```text
51 53 3A 12 A5 00 00 41 44 3A 13 00 A8 C0
```

ASCII anchors in that frame are `QS:` and `AD:`. The last four bytes are the panel IP in little-endian order:

```text
13 00 A8 C0 -> 192.168.0.19
```

`LEDProbe` now decodes this automatically:

```text
decoded: QS:VER ip=192.168.0.19 version-word=0xA512
```

`QSTECH` and `QSSIGMA` were tried on both ports and timed out, so `QS:VER` is the confirmed read-style probe so far.

## Config image notes

Sigma uses a binary `CONFIG.SYS` for panel configuration. The extracted sample has a four-byte IP field at offset `0x24`, also in little-endian order:

```text
A4 0C FE A9 -> 169.254.12.164
```

`LEDConfigPatch` creates a patched copy without touching the original:

```bash
swift run LEDConfigPatch analysis/extracted/sigma3000/CONFIG.SYS /private/tmp/CONFIG-192.168.11.6.SYS 192.168.11.6
```

Observed patch output:

```text
IP field @ 0x24: 169.254.12.164 -> 192.168.11.6
Stored bytes: 06 0B A8 C0
```

Do not push this file yet. The Sigma binary transfer command is still being decoded; the safe next step is to finish verifying the `55 A3` / `55 A7` frame wrapper and checksum against the decompiled command builders before sending any write command.

The checksum routine at `Sigma Editor.exe` `0x004a1998` is now identified. In the normal mode it returns a 16-bit additive sum over the selected byte range; an alternate mode calls another helper at `0x004a0920`. The file-transfer builder at `0x004ca5dc` prepends either `55 A3` or `55 A7`, appends the two checksum bytes, and then sends the generated frame through the active serial/TCP transport.

## TwittLED protocol notes

TwittLED is useful as a simple communication clue rather than a configuration tool. It is an old Delphi/VCL application that uses `TVaComm` for serial and `TWSocket`/Overbyte ICS for TCP. Its settings are stored in the Windows registry under `Software\Signblazer Ltd.\TwittLED`; the extracted installer does not contain a sign config file. The `SendToSign` path writes message text to the sign over serial or TCP, while the IP/config read-write workflow is in Sigma.

Run it with:

```bash
swift run LEDPanelRescue
```

## Next reverse-engineering steps

- Capture traffic from the original Windows app if it can be run in a VM on the same network.
- Finish decoding `fcn.004ca5dc` and `fcn.004ca1a8`, which build and validate binary file transfer frames.
- Once the frame format is verified, read live `CONFIG.SYS`, patch only the IP bytes to `192.168.11.6`, and push the patched image back.
- Decode `.Net`, `.fls`, `.QST`, and `.Nmg` structures enough to send actual playlists safely after networking is fixed.

## 2026-05-03 progress timing findings

- In `temp.Nmg`, speed markers are encoded as `0x0f <ascii digit>`.
  - `speed-fast-20260502-134608/temp.Nmg` has `0x0f 0x30` (`speed-0`) at offset `0xF0`.
  - `speed-slow-20260502-134533/temp.Nmg` has `0x0f 0x36` (`speed-6`) at offset `0xF0`.
- Hold markers are encoded as `0x07 <ascii digit>` (for example `hold-0`, `hold-1` in Editor captures).
- `SequentList.tmps` contains duplicated timing code bytes in the pattern `26 20 05 xx`:
  - `editor-no-black-study-20260503-025048/SequentList.tmps.after` -> `xx = 0x02`
  - `backimage-clean-live-20260503-020018/SequentList.tmps.changed.020035` -> `xx = 0x02`
  - `editor-image2image-noblack-20260503-032746/SequentList.tmps.after` -> `xx = 0x03`
- Observed `xx` families across captures:
  - `0x00`: plain Editor text sequence captures.
  - `0x01`: early backimage replay captures.
  - `0x02`: stable backimage/no-black sequence captures.
  - `0x03`: image-to-image no-black and progress-skin captures.
  - `0x13`, `0x14`: styled text/palette/speed capture families.
- Replay delay distribution from captures:
  - `backimage-clean-wire-20260503-020018.replay.tsv`: total `3580 ms` over `23` packets; large waits at packet 7 (`677 ms`), packet 22 (`1764 ms`), packet 23 (`412 ms`).
  - `editor-no-black-study-20260503-025048/wire.replay.tsv`: total `4680 ms` over `38` packets; large waits at packet 7 (`678 ms`), packet 36 (`2081 ms`), packet 37 (`629 ms`), packet 38 (`530 ms`).
  - `editor-image2image-noblack-20260503-032746/wire.replay.tsv`: total `45293 ms` over `199` packets with repeated ~`1.7 s` gaps between update groups.

## 2026-05-03 LEDctrl code updates (timing control)

- `sendProgressFrames` now enforces a speed-based frame interval floor for progress updates and logs per-frame transport time.
- Background replay packet builder now accepts `speedCode` and `holdSeconds`, then patches timing controls into generated NMG payload:
  - updates `0x0f <digit>` speed markers
  - updates `0x07 <digit>` hold markers
- Sequence timing payload in replay `02:02` packets is now patched (`26 20 05 xx`) using current hold seconds digit.
- Sequence timing payload in replay `02:02` packets is now patched (`26 20 05 xx`) using current hold seconds as a raw byte (for example `0x02`).
- Added detection/logging of source sequence timing code used by the background replay family.
