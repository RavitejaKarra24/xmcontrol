# Sound level: investigation, fix, and compatibility

Last investigated: 7 September 2026. Fix: XMControl 0.3.1.

## Result and root cause

The WH-1000XM5 can supply a changing sound-pressure estimate over its Bluetooth
control channel. The unavailable card in XMControl 0.3.0 was caused by our
parser rejecting real replies, not evidence that the headphone lacked this
feature. The connected WH-1000XM5, firmware 2.5.1, advertised support and
returned levels between **62 and 73 dB** during a read-only probe.

We initially treated `FF` in the reply's last byte as the condition for displaying
a number. That assumption was wrong. The reference project's error enum names
`00` (not playing), `01` (in call), `02` (detached), and `FF` (out of range), but
omits `03`. Its receive handler consumes the level without interpreting that
error enum. Our hardware returned `03` consistently alongside changing levels.
XMControl now accepts `03` as the observed usable-reading status and treats `FF`
as unavailable. This interpretation is hardware evidence for the tested firmware,
not a complete Sony specification for every device or firmware.

The original synthetic tests repeated the incorrect assumption and therefore
passed while the actual feature failed. Regression tests now include captured
capability and sound-pressure replies. The former suggestion to enable Safe
Listening was a general prerequisite, but did not diagnose this parser defect.

## Which models support it?

These model names refer to **WH over-ear headphones**, not WF earbuds.

| Model | Evidence for headphone sound pressure | XMControl support |
| --- | --- | --- |
| WH-1000XM4 | Sony's September 2024 compatibility matrix marks “Checking the current sound pressure” unavailable. | Not supported. We have no evidence of equivalent usable telemetry on this model. |
| WH-1000XM5 | Sony lists it as available; live replies verified here on firmware 2.5.1. | Supported and corrected in 0.3.1. |
| WH-1000XM6 | Sony documents Safe Listening; the protocol reference project separately reports Sound Pressure support. | Plausible to implement, but not implemented or tested in XMControl. |

The XM6 conclusion combines official Safe Listening documentation with a
community protocol support report; Safe Listening alone would not prove this
particular command works. The XM6 was not covered by Sony's September 2024
matrix. No XM4 or XM6 hardware was tested during this investigation.

XMControl currently selects only the WH-1000XM5 and uses XM5-specific settings
payloads. Broadening that name filter is insufficient for XM6 support: model
capabilities, command layouts, EQ, and the complete session need validation.
The decoder understands both advertised headband telemetry subtypes, but this
does not establish compatibility for the rest of the app.

Mac volume is a gain setting, not an acoustic pressure measurement. Substituting
volume percentages, digital audio amplitude, or the Mac's microphone would not
provide the same headphone-reported quantity and would require separate
calibration to estimate pressure inside a headphone. We do not fake an XM4 meter.

## Wire protocol learned

The transport is classic Bluetooth RFCOMM through Sony Serial HPC V2 service
UUID `956C7B26-D49A-4BA8-B03F-B17D393CB6E2`. The channel is discovered from SDP.
Safe Listening uses MDR V2 **table 2**, frame type `0E` (`DATA_MDR_NO2`). Table 1
uses `0C`; its commands overlap these IDs, including EQ. Frame type must be
preserved on both sending and decoding.

All bytes below are hexadecimal. Payloads exclude framing, escaping, sequence,
length, and checksum fields.

1. Complete the existing protocol handshake and initial settings sync.
2. Request table-2 capabilities: `06 00`.
3. Decode `07 00 count (function priority)...`, requiring exactly `3 + 2*count`
   bytes. Unknown function pairs are skipped. Function `50` selects headband
   subtype `00`; `52` selects headband subtype `02`. Earbud functions `51` and
   `53` are not selected by this implementation.
4. Request the current level with `5A subtype`.
5. Decode exactly four bytes: `5B subtype levelPerPeriod errorCause`.

Observed XM5 capability reply:

```text
07 00 06 41 25 50 FF F2 FF 32 03 31 FF F8 1E
```

The count is six function/priority pairs. `50 FF` advertises the first headband
Safe Listening variant. This `FF` is a **capability priority byte**, not the
reading-status byte; these fields must not be confused.

Examples captured from the connected XM5:

| Reply | Displayed level |
| --- | --- |
| `5B 00 46 03` | 70 dB |
| `5B 00 42 03` | 66 dB |
| `5B 00 43 03` | 67 dB |
| `5B 00 3E 03` | 62 dB |
| `5B 00 45 03` | 69 dB |
| `5B 00 49 03` | 73 dB |

Status handling:

| Last byte | Interpretation | Evidence |
| --- | --- | --- |
| `00` | No audio playing | Reference enum; synthetic regression |
| `01` | Unavailable during a call | Reference enum; synthetic regression |
| `02` | Headphones not worn | Reference enum; synthetic regression |
| `03` | Display the level byte | Captured live XM5 replies |
| `FF` | Unavailable; never display its level byte | Reference out-of-range sentinel; conservative handling |
| Other | Reject the reply | Unknown semantics |

Even with status `03`, level bytes `00` and `FF` are conservatively treated as
unavailable. Those bounds are validation policy, not verified acoustic limits.
Wrong subtype, opcode, length, and unknown status are rejected. Captured hardware
validation covers playback readings, not every wear/call/paused state.

## Polling, lifecycle, and UI

Capability discovery is limited to three attempts per connection/manual retry.
Only an advertised headband variant receives level queries. The app polls about
every two seconds with a common-mode timer, so menu and slider interaction does
not intentionally suspend it. A 0.25-second cadence allowance accommodates the
timer's 0.2-second scheduling tolerance; otherwise timer coalescing can accidentally
skip alternate polls. This is periodic telemetry, not an instantaneous waveform.

A reading/status expires after six seconds without an accepted response. Missing
initial replies become unavailable. Malformed or unknown replies do not refresh
the age of the previous reading. Disconnect cancels polling and clears the
session; Check again restarts discovery. Unsolicited data before discovery and
the first level request is ignored. Stale or missing numbers display a dash,
never a misleading 0 dB. The same published controller state feeds both cards.

The query path sends capability/level requests and transport ACKs. It does not
turn Safe Listening on, change playback/volume, or request listening history.
Sony documents enabling Safe Listening in Sound Connect as a prerequisite for
viewing current pressure. If correct firmware still returns no level, verify
that setting, wear the headphones, play audio through them, and reconnect.

## Meaning, privacy, and limits

The number is the headphone's reported estimate. We have not independently
calibrated it, compared it with Sony's simultaneous display, or established its
accuracy at the eardrum. The exposed field does not specify a frequency weighting
or precise averaging window, so the UI uses **dB**, not dB(A), and makes no
exposure-dose or safe-listening threshold claims.

There is no microphone/audio capture, cloud request, or stored listening history.
Readings exist only in memory. The temporary local investigation printed only
capability and level payloads, not audio or device identifiers. Production raw
Bluetooth logging remains disabled. Strict framing, bounds, checksum validation,
and separate table routing also apply to these replies.

## Validation and lessons for future changes

`./Scripts/test.sh` passes 17 regressions, including the actual capability reply,
six captured levels routed through table-2 framing and the monitor, stale expiry,
error/sentinel handling, malformed data, polling, and unsolicited-data rejection.
The raw live probe demonstrates changing replies from the physical XM5. The
release build also passes signing and bundle validation. A later full-controller
live check found the headphones disconnected, so it could not validate numeric
publications; native UI automation was also unavailable. End-to-end verification
of the rebuilt card remains pending a connected XM5. Synthetic tests remain
necessary for failure paths, but are not sufficient evidence of hardware
compatibility or acoustic accuracy.

Future model/firmware support should capture capabilities and a short read-only
exchange first, validate the real controller publications, then verify the UI.
Preserve unavailable states for unknown status values; do not expand accepted
statuses merely to make a number appear. Keep raw diagnostic capture temporary
and narrowly scoped. Verify model-specific settings before enabling another model.

## Sources

- [Sony: compatible headphones and feature matrix (September 2024)](https://helpguide.sony.net/mdr/hpc/v1/en/contents/TP0001548861.html)
- [Sony: checking the current sound pressure and Safe Listening prerequisite](https://helpguide.sony.net/mdr/hpc/v1/en/contents/TP1000752260.html)
- [Sony WH-1000XM6: Sound Connect features, including Safe Listening](https://helpguide.sony.net/mdr/2984/v1/en/contents/TP1001856857.html)
- [Reference project: WH-1000XM5 support report](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/docs/device-support/WH-1000XM5.md)
- [Reference project: WH-1000XM6 support report](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/docs/device-support/WH-1000XM6.md)
- [ProtocolV2T2.hpp: Safe Listening structs and incomplete error enum](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/libmdr/include/mdr/ProtocolV2T2.hpp)
- [ProtocolV2.hpp: capability function IDs](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/libmdr/include/mdr/ProtocolV2.hpp)
- [HeadphonesV2T2.cpp: extended-param receive handler](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/libmdr/src/HeadphonesV2T2.cpp)
- [HeadphonesV2.cpp: feature-dependent requests](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/libmdr/src/HeadphonesV2.cpp)

Reference links are pinned to the reviewed commit. XMControl implements the wire
layout in Swift and does not add a libmdr dependency.
