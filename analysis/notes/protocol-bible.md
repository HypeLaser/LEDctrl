# Sigma 3000 / JetFileII Wire Protocol — Decoded Bible

Status: 2026-05-06. Source: static RE of `SigmaEditor.exe` (Borland Delphi PE32) via Ghidra 12 headless decompile, validated against live UDP captures.

## SQ wire packet — per-entry record (the slot1 mystery)

The SQ packet structure shipped on UDP/9520 is:

```
[ 4 bytes ] 53 51 04 00              SQ header magic
[ 4 bytes ] entry_count   (LE u32)
[36 bytes ] entry record  (DT block — NOT 12 bytes as previously assumed)
[36 bytes ] entry record  ...
...
```

**The per-entry record is 36 bytes (0x24), not 12.** Earlier guess that it was `[slot1:2][slot2:2][filename:8]` (12 bytes) was wrong. The full DT block layout, decoded from `FUN_0052541c` (entry-record builder at `SigmaEditor.exe` `0x0052541c`):

| Offset | Size | Field                      | Source / formula                                           |
|-------:|-----:|----------------------------|------------------------------------------------------------|
| 0x00   | 1    | `0x44` ('D')               | hardcoded                                                  |
| 0x01   | 1    | type tag                   | switch on `func_0x00525128` → 0x54='T', 0x53='S', 0x50='P', 0x41='A', 0x46='F' |
| 0x02   | 1    | `0x0f`                     | flag byte (decompile said 0x80, wire shows 0x0f — set elsewhere) |
| 0x03   | 1    | `0x7f`                     | hardcoded                                                  |
| 0x04   | 2    | timing #1 (lo)             | `func_0x005257f8(self, uStack_26)` — 16-bit                |
| 0x06   | 1    | timing #1 byte b           | `func_0x005257f8(self, uStack_28)` — 8-bit                 |
| 0x07   | 1    | timing #1 byte c           | `func_0x005257f8(self, uStack_2c)` — 8-bit                 |
| 0x08   | 4    | `01 01 01 01`              | hardcoded                                                  |
| 0x0C   | 2    | timing #2 (lo)             | duplicate of timing #1 (lo)                                |
| 0x0E   | 1    | timing #2 byte b           | duplicate of timing #1 b                                   |
| 0x0F   | 1    | timing #2 byte c           | duplicate of timing #1 c                                   |
| 0x10   | 4    | `01 01 01 01`              | hardcoded                                                  |
| 0x14   | 2    | reserved (00 00)           | zero-init                                                  |
| 0x16   | 2    | **slot1** (LE u16)         | **`(u32 @ offset 6 of temp.Nmg) + 8`**, only if file's first 2 bytes == "NG" (0x4e 0x47) |
| 0x18   | 12   | filename                   | NUL-padded (e.g. `temp.Nmg\0\0\0\0`)                       |

### Slot1 formula — locked

```c
// FUN_0052533c @ 0x0052533c
slot1 = 0;
file = TFileStream.Create(filename, fmOpenRead);
if (file.size >= 0x12) {
    file.Read(buf, 18);
    if (buf[0..1] == "NG") {              // 0x4e 0x47
        embedded_len = u32_LE(buf[6..9]);  // bytes 6..9 of temp.Nmg
        slot1 = embedded_len + 8;
    }
}
```

The "embedded length" lives in the temp.Nmg header, not on the wire. It represents the size of the first NMG record block, not the full file. Pause / Include / effects edits change the encoded inner-block size, which is why slot1 was observed non-monotonic across sweeps when only outer file size was tracked.

### Validated example

`captures/editor-no-black-study-20260503-025048/`:

- `temp.Nmg.after` size = 28523 bytes
- bytes [6..9] = `a6 53 00 00` → 0x53a6 = 21414
- predicted slot1 = 21414 + 8 = 21422 = 0x53ae
- wire SQ packet bytes [0x16..0x17] (relative to entry start) = `ae 53` = 0x53ae ✓ exact match

## Key functions in SigmaEditor.exe

| Address     | Name                       | Purpose                                                       |
|-------------|----------------------------|---------------------------------------------------------------|
| `0x00524510`| SQ ctor (TSequent.Create)  | Builds SQ shell: `+4 = 0x5153 ('SQ')`, `+6 = 4`, `+8 = count16`, `+0x14 = count32`, `+0x18/+0x1C = TList(entries) / TList(filenames)` |
| `0x0052467c`| TSequent.AddNmg            | Allocates 36B entry, calls 0x0052541c, appends to TLists      |
| `0x00524774`| TSequent.AddTmps           | Adds `SequentList.tmps` reference (different format)          |
| `0x0052541c`| BuildEntryRecord           | Fills 36-byte DT block (slot1 written at +0x16)               |
| `0x0052533c`| ReadNmgEmbeddedLen         | **slot1 = u32@+6 + 8** if magic == "NG"                       |
| `0x0053dac4`| WriteTempNmg               | On-disk temp.Nmg writer (writes "Nmg file version:v3.99" tail) |
| `0x004ca5dc`| FrameBuilder               | Wraps payload with `55 A3` / `55 A7` + 16-bit additive checksum |
| `0x004a1998`| ChecksumAdditive           | 16-bit additive sum (transport CRC)                           |
| `0x0052442c`| SQ class metadata pointer  | VMT entry for TSequent (reached via `MOV EAX, [0x52442c]`)    |
| `0x004c2e40`| FileIndexLookup #1         | CONFIG.SYS=0, SEQUENT.SYS=1, RUNTIME.SYS=2, program.cpu=3, colorty.bin=4 |

## On-disk temp.Nmg header

```
offset 0  : 4e 47                  "NG" magic
offset 2  : 50 00                  "P" tag + flag (?)
offset 4  : 07 00                  flag word
offset 6  : <u32 LE>               embedded length (= slot1 - 8)
offset 10 : 00 00 00 00            zeros
offset 14 : ...                    NMG data follows
```

## Wire SQ packet — full validated example

```
53 51 04 00                       SQ
01 00 00 00                       1 entry
44 54 0f 7f                       DT magic
26 20 05 02                       timing #1 = 0x2026/0x05/0x02
01 01 01 01                       pad
26 20 05 02                       timing #2 (= timing #1)
01 01 01 01                       pad
00 00                             reserved
ae 53                             slot1 = 0x53ae
74 65 6d 70 2e 4e 6d 67 00 00 00 00  filename "temp.Nmg"
```

## Implications for `SigmaClient.swift`

The `SigmaClient.swift:1325-1330` per-entry record format must be widened from 12 bytes to **36 bytes** with the layout above. Slot1 must be computed dynamically per upload from the temp.Nmg payload (`u32_LE @ +6 + 8`), not guessed.

## Patch landed — `SigmaClient.swift`

`makeSequenceFile(entries:)` rewritten 2026-05-06: header now `53 51 04 00 + le32(count)`, per-entry record now 36 bytes (was 16 — wrong). `SigmaSequenceEntry` gained optional `nmgPayload`; slot1 computed per-entry via `sequenceSlot1(_:)` = `u32_LE(payload[6..9]) + 8` if `payload[0..1] == "NG"`, else 0. Build green. FLW 44-byte branch left untouched.

## Video / `.flw` / `.gif` — discovery

`sigma3000_extracted/` ships FFmpeg DLLs (`avcodec-56`, `avformat-56`, `avutil-54`, `avdevice-56`, `avfilter-5`) + `czVideoDecode.dll` + `czRender.dll` + `czRenderer.exe` + `czRenderSchedule.exe`. The `.FLW` files emitted by Sigma's "movie to flw" converter are **FLV containers** (magic `46 4C 56 01` = "FLV\x01"), not a sign-native frame format.

Architecture inference (to verify with capture):

1. Sigma Play opens any video → FFmpeg transcodes to FLV (`*.FLW`).
2. `czVideoDecode.dll` decodes FLV frames PC-side.
3. `czRender.dll` dithers each frame to the sign's pixel grid + palette (80×7 R/G for our TFI-7X80-50RG = 560px × 2bpp ≈ 140 B/frame).
4. `czJetFileII.dll` wraps each frame in NMG records and ships over UDP/9520 — likely a sequence of small bitmap files, played as a slideshow by the sign firmware.

**Implication: the sign almost certainly does NOT decode video natively.** Video playback is PC-side render-and-stream. To replicate this in LEDctrl: FFmpeg decode → 80×7 R/G dither → per-frame NMG bitmap → SQ sequence file referencing N frames.

`.gif`: not present in the extracted distribution. Likely supported only on full-colour Sigma signs via a separate path; needs separate capture to confirm.

### czJetFileII.dll exports relevant to video

```
_czMPUSetVideoArg@8        sets video mode args on sign's main MPU
_czShowBmpToNmg@16         converts a BMP frame to an NMG record
_czShowMsgToNmg@28         (text path equivalent)
czPlayNextFrame            internal — advance to next frame (private symbol)
czPlayContinue             internal — resume playback
czContinueTiming           internal — timing continuation
```

Plus error string: *"Current display file oversized and can not be read. Please use extended reading command!"* and *"Start filling the last frame!"* — confirms an oversize-file chunk path and frame-fill state machine.

### Sigma Play accepts video → DirectShow → frames

Sigma Play.exe imports DirectShow / VMR (`OnGraphVideoSizeChanged`, `OnGraphVMRRenderDevice`, `IVideoWindow`, `IDDrawExclModeVideo`). File picker accepts: `*.AVI;*.GIF;*.MPEG;*.MPG;*.MPE;*.FLV;*.FLA;*.VOB;*.WMV;*.DAT;*.ASF;*.WMA;*.MP4;*.MOV;*.QT;*.MPGA;*.3GP`. Internal data-type tags: `dtAVIVideo`, `dtDigitalVideo`, `dtMMMovie`, `dtSequencer`, `dtVideodisc`. So Sigma Play *previews* with DirectShow and *transcodes* with FFmpeg, then ships frames via JetFileII.

### Wire protocol for video — most likely

PC-side per-frame pipeline:

1. FFmpeg decode video frame (RGB)
2. PC-side dither → 80×7 R/G bitmap (~140 B for our sign)
3. `czShowBmpToNmg` wraps frame as an NMG record
4. `czFOpen`/file-send on F: drive (e.g. `F:\F\frameNNN.Nmg`) OR a single multi-frame container
5. SQ sequence file references the frames; `czPlayNextFrame` advances the sign's playhead

Open question: single multi-frame `.flw` blob streamed via `czMPUSetVideoArg` OR N small `.nmg` frames in an SQ playlist. **Capture-required to disambiguate.**

### Capability for our TFI-7X80-50RG (80×7 R/G)

This sign is unlikely to have a hardware video decoder; expect PC-side render-and-stream. 80×7 × 2bpp ≈ 140 B/frame; at 15 fps that's 2.1 KB/s — comfortably within UDP MTU and the sign's text-update bandwidth. Realistic ceiling: 10–20 fps, single-line tickers, no audio.

`.gif`: file picker lists `.GIF` but no GIF-specific code paths surfaced in strings. Likely treated as just another video input fed to FFmpeg.

### Capture plan (to validate)

1. Install Sigma Play in a Windows VM with point-to-sign network reachability (192.168.11.6:9520).
2. Convert short clip → "movie to flw", send to sign.
3. tcpdump UDP/9520 for the entire send.
4. Compare bytes against decoded text-path SQ format. Identify:
   - filename(s) on F: drive (single `.flw`? sequence of `.nmg`?)
   - SQ entry type tag
   - per-frame timing field encoding
   - whether `czMPUSetVideoArg` puts the sign in a special receive mode

## Other unsolved fields (followup)

- `[0x02]` — wire shows 0x0f, decompile said 0x80. Likely set in caller path or initialised by alloc fill.
- `[0x14..0x15]` — observed 00 00 in wire; decompile didn't write this region. Possibly zero-init from `FUN_00402784(0x24)` (allocator zeroes block).
- Type tag (`[0x01]`) values `T/S/P/A/F` map to 5 sequence types — switch in `FUN_0052541c` at `func_0x00525128`. T=text, S=?, P=picture?, A=animation?, F=font/fixed?
- `func_0x005257f8` — encoder for date/time word into the timing fields.

---

## Live read API (port complete — 2026-05-06)

`SigmaClient.queryRPC(major:sub:param3:param4:)` ported from FUN_1000f590 in czJetFileII.dll. Live tested against TFI-7X80-50RG @ 192.168.11.6:9520.

Request frame layout (16-byte header):
```
[55 a3] [crcHi crcLo]                       — magic + X25 CRC over body
[u32 LE param4_len] [01 01]                  — payload length, dev1, dev2
[u16 LE seq] [major] [sub] [u16 LE words]    — words = param3 length / 4
[param3 (words*4 bytes)]
[param4 (param4_len bytes)]
```

Response magic: `55 a4` (vs request `55 a3`). Body status word `0x9000`/`0x9005` lives at bytes 16-17.

### Working RPCs (TFI-7X80-50RG, 80×7 R/G basic sign)

| major.sub | name              | request      | response body                                     |
|-----------|-------------------|--------------|---------------------------------------------------|
| 01.16     | czReadBrightInfoExt | none       | `01 19 00 00 00 00 00 00` — mode=auto, level=0x19 (25) |
| 01.1B     | czReadPCBID       | 4 zero bytes | `05 90 [u32 LE pcb-id]` — id = 0x00200120         |
| 03.01     | network info      | none         | `12 A5 FF FF 06 0B A8 C0 01 01 00 00` — embeds IP `c0:a8:0b:06` (192.168.11.6) |
| 05.01     | clock/datetime    | none         | `26 20 05 06 18 01 03 0C` — same shape as DT timing tag (year=0x26, mon=0x05, day=0x06) |
| 07.01-04  | counters/flags    | none         | `11 90`, `01 72`, `01 73`, `02 74` — distinct status bytes per sub |
| 08.03     | unknown           | none         | `05 83 …` |
| 0A.01,03  | unknown           | none         | `32 90 …` (0x32=50; LCD module count?) |

### Generic NAK shape

Unsupported reads return 6 bytes: `05 90 20 01 20 00`. The `0x9005` prefix appears in *both* a successful read (PCBID) and the unknown shape, so the discriminator is the trailing payload, not just the status.

### CLI

`LEDSigmaQuery <host> <pcbid|brightness|rpc <major> <sub> [param3-hex] [param4-hex]>`
