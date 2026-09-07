# Live sound pressure

The Sound pressure card displays the WH-1000XM5's own current sound-pressure
estimate in whole decibels. It is available in the menu bar panel and the full
dashboard. It does not derive a level from the Mac volume slider or record audio.
There is no microphone permission, audio capture, network service, or persistent
listening history.

## Bluetooth protocol

Safe Listening belongs to Sony MDR V2 **table 2**, frame type `0x0E`
(`DATA_MDR_NO2`). Table 1 (`0x0C`) contains overlapping command IDs, including EQ,
so table-2 payloads must be routed separately.

1. After the existing headphone setup completes, request table-2 support with
   `[06 00]`.
2. Validate `[07 00 count (function priority)...]`, including the exact pair count.
   Function `50` selects headband subtype `00`; function `52` selects subtype `02`.
   Unsupported/earbud-only capabilities do not trigger sound-pressure queries.
3. Poll `[5A subtype]` about every two seconds.
4. Decode an exact four-byte reply `[5B subtype levelPerPeriod errorCause]`.
   Known error causes are `00` (not playing), `01` (in call), and `02` (detached).
   `FF` is the protocol's out-of-range/not-applicable error value; only this case
   with a nonzero, non-`FF` level is displayed as a number. Unknown error values,
   wrong subtypes, and malformed replies are rejected.

Discovery is limited to three attempts per connection or manual retry. Missing
level replies show an unavailable state; a previously received status expires
after six seconds and clears the number. Polling resumes automatically when the
headphones reply. Disconnect invalidates the polling timer and clears all data.
The timer uses the common run-loop mode so slider/menu interaction does not
freeze readings.

The app sends only capability and level queries plus normal frame ACKs. It does
not send Safe Listening setting or history-transfer commands. If firmware does
not return a usable reading, enable Safe Listening in Sony Sound Connect, wear
the headphones, play audio, then reconnect to the Mac app.

## Interpretation

This is headphone telemetry, not an independently calibrated measurement of
pressure at the eardrum or environmental noise. The exposed reply does not
specify frequency weighting or an exact averaging window, so the UI says **dB**,
not dB(A), and does not assign hearing-safety thresholds or calculate exposure.
A missing, stale, or error response is shown as **—**, never as 0 dB.

## Evidence and validation

- [Sony: Checking the current sound pressure](https://helpguide.sony.net/mdr/hpc/v1/en/contents/TP1000752260.html)
  documents the feature and the Safe Listening prerequisite.
- [mos9527/SonyHeadphonesClient: WH-1000XM5 support](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/docs/device-support/WH-1000XM5.md)
  reports support for sound pressure on the XM5.
- Wire definitions were cross-checked against that project's
  [ProtocolV2T2.hpp](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/libmdr/include/mdr/ProtocolV2T2.hpp),
  [ProtocolV2.hpp](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/libmdr/include/mdr/ProtocolV2.hpp),
  and [HeadphonesV2.cpp](https://github.com/mos9527/SonyHeadphonesClient/blob/965c458116d40827494726447de5f07eb50efcb8/libmdr/src/HeadphonesV2.cpp).
  XMControl implements the wire layout in Swift without adding a libmdr dependency.

Run `./Scripts/test.sh` for protocol and state-machine regressions. Test vectors
for sound pressure are constructed from the protocol definitions; they are not
claimed to be captured packets or an acoustic calibration. Hardware validation
requires an actively connected, worn XM5 with audio playing.
