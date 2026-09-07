# Security and privacy

XMControl communicates directly with a paired, currently connected Sony
WH-1000XM5 through its advertised classic Bluetooth control service. The
app has no internet client, server, account, telemetry, or third-party package
dependencies. A saved EQ curve is stored locally in macOS preferences.

## Protections

- Incoming frames have a 4 KiB payload limit, exact length and checksum checks,
  strict escaping, valid sequence/type checks, and recovery after corrupt data.
- Replies are checked for the expected subtype, band count, value ranges, and
  printable device text before they reach UI state. Sound-pressure telemetry uses
  a separate table-2 route, with capability checks and stale-reading expiry.
  Readings stay in memory and are never recorded or uploaded; no microphone or
  system audio capture is used.
- Callbacks from old RFCOMM channels are ignored. Failed writes, stalled service
  discovery, and incomplete setup cause a clean retry. Queued slider edits are
  cancelled when disconnected or superseded by a preset.
- Only paired, connected devices named `WH-1000XM5` are selected, and the V2
  service must be advertised. Other models have different command layouts.
- Raw Bluetooth bytes are never logged. Diagnostic messages are off by default;
  opt-in messages use private interpolation in Apple's unified logging system.
- The packaged app uses hardened runtime without exception entitlements.
  The installer verifies a staged copy before replacing the existing app.
- CI has read-only repository permissions and pins its checkout action to a
  commit. Build products, credentials, and logs are excluded from source control.

## Boundaries

Bluetooth pairing is the trust boundary; a device name and service UUID are
compatibility filters, not cryptographic device authentication. The protocol's
checksum detects corruption, not a malicious paired device. Do not pair devices
you do not trust. The parser checks reduce attack surface but are not a formal
security audit.

The app is not App Sandbox constrained. The local build is ad-hoc signed, not
Developer ID signed or notarized. Hardened runtime does not provide notarization
or App Store review. No installer step disables Gatekeeper or removes quarantine.

Earlier versions wrote raw traffic to `~/Library/Logs/XMControl.log`. This version
no longer writes that file; an existing file is left untouched. You may remove
it if you no longer need the old diagnostics.

## Reporting

Use this repository's private GitHub vulnerability reporting option if enabled.
Avoid posting credentials, Bluetooth identifiers, or private diagnostics in a
public issue. Reports should include the affected version, reproduction steps,
and expected impact.

## Reference

The logging and signing configuration follow Apple's documentation for
[Logger](https://developer.apple.com/documentation/os/logger) and
[hardened runtime](https://help.apple.com/xcode/mac/current/en.lproj/devf87a2ac8f.html).
