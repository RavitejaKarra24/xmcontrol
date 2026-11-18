# sony_for_mac

Your listening space, right on your Mac. A native menu bar companion for the
**Sony WH-1000XM5**, built with Swift and SwiftUI.

Control noise cancelling, transparency, equalizer, playback, and headphone
settings through a direct Bluetooth connection. No Sony account, cloud,
analytics, Electron, or external package dependencies.

## A profile for your moment

| Profile | Listening mode | EQ | Speak-to-Chat |
| --- | --- | --- | --- |
| Focus | Noise cancelling | Flat and balanced | Off |
| Commute | Noise cancelling | Gentle bass lift | Off |
| Aware | Transparency, level 20 | Flat and balanced | Off |
| Podcast | Noise cancelling | Reduced bass, clearer mids | Off |

These are app-authored starting points, not Sony factory presets. Each uses
six-band custom EQ. Profiles leave volume, DSEE, Bluetooth priority, and power
preferences unchanged. Aware lets ambient sound through but does not guarantee
awareness of your surroundings.

## Controls

- **Live sound pressure:** a headphone-reported dB estimate, refreshed about every
  two seconds, with explicit unavailable and stale states. Available in the quick
  panel and dashboard. Enable Safe Listening in Sony Sound Connect if needed.
  Verified with live XM5 firmware 2.5.1 replies. Read the
  [sound-level investigation](sound_level.md) for protocol details and model support.

- **Quick panel:** listening profiles, ambient sound, and playback from the menu
  bar, with an **All controls** shortcut to the full dashboard. When another
  device is connected too, a **Play here** switch appears.
- **Listening mode:** noise cancelling, transparency (1–20), and off, with Focus
  on Voice in transparency mode.
- **Equalizer:** Sony preset selection and six custom bands: Clear Bass, 400 Hz,
  1 kHz, 2.5 kHz, 6.3 kHz, and 16 kHz. Reset to flat or save/restore one personal
  curve on this Mac. Use Up/Down arrow keys on a focused band for precise edits.
- **Smart audio:** DSEE Extreme; Speak-to-Chat, sensitivity, and resume delay.
- **Connection:** sound quality or connection stability priority, and the active
  codec.
- **Headphone controls:** touch panel on/off (Siri is restored when it comes
  back on), the NC/AMB button's cycle, pause when taken off, and voice guidance.
- **Devices (multipoint):** connect to two devices, switch automatically to the
  device that starts playing, and the paired-device list. Play from, connect,
  disconnect, or forget each device, and put the headphones in pairing mode.
  This Mac is marked and can't be disconnected from here.
- **Confirmations:** cautions the headphones raise (for example before
  reconnecting) appear as a Continue/Cancel banner.
- **Automation:** apply a profile while a chosen app is in front, global
  shortcuts (⌃⌥⌘N next mode, ⌃⌥⌘1–4 profiles), and `sonyformac://` links for
  Shortcuts. Shortcuts are off by default and need no extra permissions.
- **Playback:** volume (0–30), play, pause, and track skip.
- **Device:** battery and firmware, wear-based auto power-off, and a confirmed
  power-off action. Reconnects automatically when the headphones become available.
- **Accessibility:** labeled controls, visible EQ keyboard focus, improved text
  contrast, and reduced-motion-aware animations.

Controls become available after the initial headphone settings sync. Changes
are sent immediately (sliders are debounced); profiles and EQ selections request
fresh state afterward. Multi-setting profiles are not atomic: a disconnect can
interrupt application. Reconnect and apply again if necessary.

## Build and run

Requires **macOS 14 or later** and Apple's Command Line Tools:

```sh
xcode-select --install
./Scripts/run.sh
```

Allow Bluetooth access when macOS asks. Connect the WH-1000XM5 to your Mac as an
audio device in Bluetooth Settings. Click the headphones menu bar icon for quick
controls, or right-click it for Reconnect and Quit.

To install a local build into `~/Applications`:

```sh
./install.sh
```

Use `INSTALL_DIR=/Applications ./install.sh` to choose another installation
folder, or `OPEN_APP=0 ./install.sh` to install without launching. Add the app to
Login Items in System Settings if you want it to start at login.

This app was previously named XMControl. The installer quits and replaces an
`XMControl.app` in the same folder, and a saved EQ curve carries over on first
launch.

Build products are ad-hoc signed with hardened runtime for local use. They are
not Developer ID signed or notarized for general binary distribution.

## Development and tests

```sh
swift build
./Scripts/test.sh                 # works with Command Line Tools alone
swift test                        # alternative: requires full Xcode / XCTest
./Scripts/package_app.sh release  # build, package, sign, and verify
./Scripts/make_icon.sh            # regenerate AppIcon.icns from AppIcon.svg (needs librsvg)
```

The app icon's source is `Resources/AppIcon.svg`; the generated
`Resources/AppIcon.icns` is committed so builds need no extra tools.

The regression suite covers every frame split, all escaped byte values, corrupt
and oversized input, deterministic random streams, payload validation, preset
wire layouts, saved preference validation, disconnected action guards, sound-pressure
capabilities, reply validation, polling, and stale data handling, captured
device-control and multipoint replies, alert handling, and URL commands. CI
runs the tests and packaging on macOS. Live Bluetooth behavior still requires
headphones; software tests are not a hardware compatibility certification.

## Protocol and compatibility

The WH-1000XM5 exposes Sony's Serial HPC V2 service over **classic Bluetooth
RFCOMM**, using service UUID `956C7B26-D49A-4BA8-B03F-B17D393CB6E2`. The app discovers
the RFCOMM channel from the service record; it does not use BLE GATT.

The transport feeds bounded, checked MDR frames into a main-actor controller,
which handles setup and publishes state to SwiftUI. Outgoing commands use the
existing XM5-specific payload layouts in this project.

Only the **WH-1000XM5** is supported. XM6 support has not been implemented or
validated; XM3/XM4 and WF earbuds also need model-specific integration. Renamed headphones are not selected automatically. Multipoint
on/off and device connect/forget actions follow the reference layouts but were
not toggled on hardware; see [Docs/DeviceSettings.md](Docs/DeviceSettings.md).
The Mac must have an active audio link;
a connection only to a phone is not enough. Some factory preset IDs can vary
by firmware; the four app profiles use custom curves instead.

Protocol research references:
[Plutoberth/SonyHeadphonesClient](https://github.com/Plutoberth/SonyHeadphonesClient),
[argjentsahiti/aura-xm5](https://github.com/argjentsahiti/aura-xm5),
[pratikaman/sony-wh1000xm5-mac-control](https://github.com/pratikaman/sony-wh1000xm5-mac-control),
and [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge).

sony_for_mac is an independent project, not affiliated with or endorsed by Sony.

## Privacy and diagnostics

Raw Bluetooth payloads are never logged. Optional private diagnostics use
Apple's unified logging system and are enabled only for the process launched
with `SONY_FOR_MAC_DIAGNOSTICS=1`. Saved EQ values stay in local macOS preferences.
Read [SECURITY.md](SECURITY.md) for protections, limits, and legacy log handling.
