# SQ Block + NMG Format Rewrite Plan

## Verified ground truth (5 A-set captures, 2026-05-06)

### CRC validate packet (56B, opcode 0x02:0x0e)
```
55 a3 [chk2] 00 00 00 00 01 01 [seq2] 02 0e 0a 00
D:\T\temp.Nmg\0\0 [pad to 32B from path start]
[00×9] [NMG_len_LE32] [CRC_BE16] 00 00
```
- CRC16-X25 (poly 0x1021, init 0xFFFF, refin/refout, xorout 0xFFFF)
- Domain: NMG body from `01 5a 30 30` magic for `NMG_len` bytes
- Wire stores BE16 (big-endian)

### SequentList write (84B, includes 44B SQ block)
```
count_LE32(4) + "SQ\x04\x00"(4) + ver_LE32=1(4) + "DT\x0f\x7f"(4)
+ tsA(8) + tsB(8) + slot1_LE16(2) + slot2_LE16(2) + filename_8B(8) = 44
```

### Timestamp (8B, tsA == tsB across all 5 captures)
| Capture | Local time | tsA bytes | byte0..3 decode |
|---|---|---|---|
| A1 | 11:34 BST | `26 20 05 11 01 01 01 01` | (yrLo=26, yrHi=20, mo=05, hr=11) BCD |
| A2-WON | 13:12 BST | `26 20 05 13 01 01 01 01` | (yrLo=26, yrHi=20, mo=05, hr=13) |
| A2-WOFF | 13:27 BST | `26 20 05 13 01 01 01 01` | (yrLo=26, yrHi=20, mo=05, hr=13) |
| A4-WON | 14:01 BST | `26 20 05 14 01 01 01 01` | (yrLo=26, yrHi=20, mo=05, hr=14) |
| A4-WOFF | 14:07 BST | `26 20 05 14 01 01 01 01` | (yrLo=26, yrHi=20, mo=05, hr=14) |

**Format**: bytes 0..3 = (yrLo, yrHi, mo, hr) BCD-encoded local time at message-creation. Bytes 4..7 = `01 01 01 01` (uninitialised or default day/min/sec/wd). Editor only sets first 4 of 8 timestamp bytes.

### Slot1 (timing/dwell — semantics still unclear)
| Capture | slot1 dec | slot1 hex | ASCII |
|---|---|---|---|
| A1 | 3000 | 0x0BB8 | (none) |
| A2-WON | 8224 | 0x2020 | "  " |
| A2-WOFF | 29300 | 0x7274 | "tr" |
| A4-WON | 22240 | 0x56E0 | (none) |
| A4-WOFF | 22240 | 0x56E0 | (none) |

**Hypothesis**: uninitialised stack memory leaked into emit by Editor v3.99. Evidence:
- A4-WON ≡ A4-WOFF identical despite different content → not derived from payload
- 0x2020 = literal spaces from string buffer
- 0x7274 = "tr" substring fragment
- A1 = 3000 plausible "30s default" template

If junk: sign ignores. Emit zero. Verify by sending zero-slot1 NMG and observing render unchanged.

### Slot2
Confirmed = NMG body length (178, 201, 200, 193, 193).

### Filename
8B `temp.Nmg` (NOT 12B as Swift currently emits).

## Swift bugs

### `SigmaClient.swift:1571-1591` — makeSequenceFile non-FLW path
Wrong layout:
- Header: emits "SQ\x04\x00" then count → wire is count then "SQ\x04\x00"
- Missing ver_LE32(=1) field (4B)
- Per-entry 36B uses driveCode/fileType/timing × 2/reserved/slot1/12B-filename
- Wire 36B per-entry uses (after "DT\x0f\x7f"): tsA(8) + tsB(8) + slot1(2) + slot2(2) + filename(8)
- Slot2 entirely absent from Swift emit
- Filename emitted as 12B not 8B

### `sequenceSlot1` (line 1594) — wrong field semantics
Returns `nmg[6..9]_LE32 + 8` if payload starts with "NG". For Swift's own `NGP\x00` NMG format, this approximates body length — i.e. computes what the wire calls **slot2**, not slot1. Function is mislabelled.

### NMG format mismatch
- Swift `makeNmg` (line 1000) emits `NGP\x00 ...` (older format)
- Vendor v3.99 wire emits `01 5a 30 30 ...` (NoteNmg v3.99 format)
- Sign accepted Swift's NGP NMG and rendered "RTC TEST" → backward-compatible at sign side
- For full vendor parity (CRC validate packet matching), need v3.99 NMG path

## Proposed changes (ordered, atomic)

### Phase 1: SQ block layout fix (low risk)
**File**: `SigmaClient.swift:1550-1604`

1. Replace `makeSequenceFile` non-FLW path with verified 44B-per-entry layout:
   ```swift
   var data = Data()
   data.append(contentsOf: le32(UInt32(entries.count)))   // count first
   data.append(contentsOf: [0x53, 0x51, 0x04, 0x00])      // "SQ\x04\x00"
   data.append(contentsOf: le32(1))                        // ver
   data.append(contentsOf: [0x44, 0x54, 0x0f, 0x7f])      // "DT\x0f\x7f"
   for entry in entries {
       let ts = sigmaCreationTimestamp()      // 8B BCD (yrLo,yrHi,mo,hr,01,01,01,01)
       data.append(ts); data.append(ts)
       data.append(contentsOf: le16(0))       // slot1 = 0 (junk on vendor side)
       data.append(contentsOf: le16(UInt16(entry.length)))  // slot2 = NMG body length
       data.append(contentsOf: fixedBytes(entry.filename, count: 8))  // 8B not 12B
   }
   ```
2. Add helper `sigmaCreationTimestamp() -> Data` returning 8B BCD timestamp from `Date()`.
3. Drop `sequenceSlot1` helper — no longer needed.
4. Verify FLW path (entries.count == 1, fileType == .flw) untouched — still emits compact 44B shape.

### Phase 2: CRC validate packet (medium risk)
Add new `sendCrcValidate(path:, length:, crc:)` that emits opcode 0x02:0x0e with NMG_len LE32 + CRC BE16 trailer. Hook into sendNmg/sendFile post-write step.

### Phase 3: NMG v3.99 emit (high risk, deferred)
Port `01 5a 30 30` NMG format. Requires deep dive into Editor v3.99 disassembly. Defer until current Phase 1+2 verified live.

## Test plan
- Phase 1: `swift build` clean. Hex-compare emitted SequentList vs A1 capture (slot1=0 expected difference).
- Phase 1 live: send to 192.168.11.6, confirm render unchanged.
- Phase 2: capture our send + diff against vendor capture for CRC validate packet bytes.

## Out of scope
- Slot1 semantics (tracked separately; needs Editor knob test capture)
- Day-of-month / minute / second timestamp bytes (Editor doesn't set; mirror its behaviour)
- Phase 3 v3.99 NMG (separate task)
