# Device settings, multipoint, and automation

Added in sony_for_mac 0.5.0. Investigated 18 November 2026 on a WH-1000XM5,
firmware 2.5.1.

## Method

1. A read-only probe sent only GET requests and recorded the replies.
2. Each reversible setter was sent, read back, restored, and read back again.
   The touch panel, NC/AMB button, pause-when-removed, voice guidance, and
   automatic source switching were all returned to their original values.
3. Multipoint on/off, pairing mode, connect, disconnect, forget, and playback
   switching were **not** exercised on hardware, because they affect other paired
   devices. Their layouts come from libmdr's generated structs, and the shapes
   they depend on (device list, address format, inquired types) were captured live.

Captured replies are regression tests in `Tests/sony_for_macTests/DeviceSettingsTests.swift`.
The paired-device fixture keeps the captured layout but uses synthetic names and
addresses.

## Capabilities the XM5 reports

Table 1 (`06 00`) lists 33 functions. Besides those the app already used, the
relevant ones are `D1`/`D2` (general settings), `F1` (playback control by
wearing), `F4` (voice assistant), `69` (NC/AMB button), `90` (fixed-message
alerts) and `12` (codec indicator). Table 2 lists `41` (voice guidance on/off
only, no volume), `32` (device management with class of device), and `31`
(source switch control).

Not implemented, with reasons:

| Function | Why not |
| --- | --- |
| Voice guidance volume | Not advertised; the volume query gets no reply. |
| Timed auto power-off | Only the wear-detection variant (`25`) is advertised. |
| Quick Access (`FD`) | Launches Spotify, Endel or Apple Music on a phone. |
| Google Assistant / Alexa | Needs the assistant's phone app for setup. |
| `B0`/`B6`/`B7` SAR and head tracker | Used by 360 Reality Audio on Android. |
| `F9` reset settings | Factory reset; deliberately left out. |
| `32` firmware update | Out of scope and risky. |

## Wire layouts

All bytes are hexadecimal payloads, without framing.

| Feature | Request | Reply / notification | Values |
| --- | --- | --- | --- |
| Pause when taken off | `F6 01`, set `F8 01 v` | `F7 01 v`, `F9 01 v` | `00` on, `01` off |
| NC/AMB button | `66 30`, set `68 30 m` | `67 30 m`, `69 30 m` | `01` NC/Amb/Off, `02` NC/Amb, `03` NC/Off, `04` Amb/Off |
| Voice assistant | `F6 04`, set `F8 04 a` | `F7 04 a`, `F9 04 a` | `30` device assistant, `FF` none |
| General setting name | `D0 <slot> 01` | `D1 <slot> 00 01 <len> <name> <len> <summary>` | slot `D1` `TOUCH_PANEL_SETTING`, `D2` `MULTIPOINT_SETTING` |
| General setting value | `D6 <slot>`, set `D8 <slot> 00 v` | `D7 <slot> 00 v`, `D9 …` | `00` on, `01` off |
| Alerts | enable `94 00 00` | `99 00 <message> <action>` | answer `98 00 <message> 01` (continue) or `00` |
| Codec | `12 02` | `13 02 c` | `02` AAC |
| Voice guidance (table 2) | `46 01`, set `48 01 v` | `47 01 v <lang>`, `49 01 v` | `00` on |
| Pairing mode (table 2) | `32 02`, set `34 02 m 00` | `33 02 m s`, `35 …` | `m` `01` discoverable |
| Paired devices (table 2) | `36 02` | `37 02 n {addr[17] slot cod[3] len name}… playbackSlot` | `slot` non-zero when connected |
| Auto switch (table 2) | `36 01`, set `38 01 v` | `37 01 v`, `39 01 v result` | `01` follow the playing device |
| Connect / disconnect / forget | `3C 02 <action> addr[17]` | `3D 02 <action> <result> addr[17]` | action `01`/`00`/`02` |
| Play from device | `3C 01 addr[17]` | `3D 01 <result> addr[17]` | result `00` success |

Addresses are 17 ASCII characters (`AA:BB:CC:DD:EE:FF`) and are sent back
exactly as the headphones reported them.

## Findings that shaped the implementation

- **Touch panel needs the alert handshake.** Without `94 00 00`, `D8 D1 00 01`
  is silently refused (the device notifies the panel still on). With alerts
  enabled, it sends caution `0A`; answering `98 00 0A 01` applies the change.
  The app now enables alerts for every session and shows a Continue/Cancel
  banner for cautions the user hasn't already confirmed. Informational cautions
  that directly follow the user's own change are confirmed automatically and
  shown as a notice.
- **Turning the touch panel off clears the voice assistant** (`F9 04 FF`), and
  turning the panel back on does not restore it. The app restores the device
  assistant (`F8 04 30`) after the user turns the panel back on, and offers a
  **Use Siri** button if it's still unassigned.
- **Commands must wait for ACKs.** Sending about 20 requests back to back made
  the XM5 drop most of the new ones. `SonyLink` now queues commands and sends
  the next after the previous frame's ACK, or after a 0.6-second timeout.

## Mac automation

- **Profiles by app:** while a chosen app is frontmost, its profile is applied.
  Switching to another app restores the profile (or settings) from before,
  unless you changed something in between. sony_for_mac's own windows never
  trigger a switch.
- **Keyboard shortcuts:** ⌃⌥⌘N cycles Noise cancelling → Transparency → Off;
  ⌃⌥⌘1–4 toggle Focus, Commute, Aware, and Podcast. They use Carbon
  `RegisterEventHotKey`, which needs no Accessibility permission. Off by default.
- **URL scheme:** `sonyformac://mode/{nc|transparency|off|next}` and
  `sonyformac://profile/{focus|commute|aware|podcast|off}`, for Shortcuts'
  "Open URLs" action or `open` in a script. Commands that arrive before the
  headphones are ready run once they are, if that's within 60 seconds. Only
  reversible listening changes are exposed.

Verified live: URL mode change, ⌃⌥⌘N while another app was frontmost, and a
Finder → Aware rule applying and then restoring noise cancelling.

Not implemented: Wi-Fi-based switching (reading the network name needs Location
Services permission), calendar-based switching (needs Calendar access), and
Focus-mode detection (no public API; use a Shortcuts automation with the URL
scheme instead).
