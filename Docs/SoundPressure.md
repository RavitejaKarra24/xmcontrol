# Live sound pressure

XMControl shows the WH-1000XM5's own sound-pressure estimate in the menu bar
panel and full dashboard, refreshed about every two seconds. Version 0.3.1 fixes
rejection of the `03` status observed on XM5 firmware 2.5.1 during live playback.

Enable Safe Listening in Sony Sound Connect if needed, wear the headphones, and
play audio. Missing or stale readings display a dash. The number is headphone
telemetry, not an independently calibrated measurement; no microphone access,
audio capture, or stored listening history is involved.

See [sound_level.md](../sound_level.md) for the complete investigation, captured
replies, corrected status interpretation, validation, sources, and XM4/XM5/XM6
compatibility findings. XMControl currently supports only the WH-1000XM5.
