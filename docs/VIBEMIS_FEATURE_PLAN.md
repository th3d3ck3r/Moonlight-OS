# 🌘 Eclipse — lightweight frontend feature ideas

Working proposal, not an instruction to implement every item. See [Eclipse implementation and limits](ECLIPSE_FRONTEND.md) for current source features. The user has authorized a candidate build after source/theme validation; publication still awaits physical validation.

## Control center

A right-side panel using the existing black/crimson theme, selected accent, rounded controls, and visible keyboard/controller focus. Compact mode contains network, Bluetooth, host status, battery, volume/mute, audio output, screen brightness, keyboard brightness, and power. Expand a section for detailed controls; keep uncommon settings in a separate page.

During a stream, local panel navigation must not reach the remote host. Closing it must restore input capture and focus. Test this explicitly before enabling the panel in streaming sessions. Do not imply CPU/RAM readings are local when they come from Vibepollo.

## Feature menu

| Area | Candidate features |
|---|---|
| Wi-Fi | Scan/connect; saved networks; password entry; signal; disconnect; hidden networks; enterprise setup; airplane mode; optional hotspot; IP/address details; DNS settings; connectivity test; captive-portal handoff when a browser exists |
| Bluetooth | Scan/pair/reconnect/disconnect; confirmed forget; pairing progress; PIN/confirmation prompts; device battery where exposed; controller/headphone grouping; preferred audio device; radio toggle; adapter selection |
| Audio | Output/input selection; system/stream volume; mute; speaker/AirPods switching; microphone privacy toggle; test sound; channel balance; safe volume ceiling; quality/latency presets; supported codec display |
| Display | Resolution/refresh rate; UI scale; fullscreen/windowed; external monitor selection; mirror/extend where supported; screen brightness; idle blanking; aspect ratio; safe mode-change countdown with automatic rollback |
| Keyboard/trackpad | Pointer speed; acceleration; natural scrolling; tap-to-click; drag behavior; keyboard layout; keyboard backlight; Fn behavior; configurable shortcuts; local-versus-host shortcut policy |
| Controllers | Device list; battery where exposed; input/rumble test; dead zones; mapping; preferred controller; navigation hints; reconnect shortcut; controller-only operation; per-device profiles |
| Hosts | Discovery/manual entry; pairing; favorites; rename; Wake-on-LAN; reconnect; connection history; host settings URL; Vibepollo/Sunshine management shortcut; host availability; last-used host |
| Launcher | Search; recent hosts/apps; favorites; pinned applications; optional auto-connect/auto-launch; artwork caching with a size limit; keyboard/controller navigation; desktop-oriented and couch-oriented layouts |
| Streaming | Per-host/app resolution, FPS, bitrate and codec; hardware decoding preference; HDR where supported; audio routing; surround mode; aspect-ratio policy; reconnect policy; bandwidth presets; desktop versus gaming presets |
| Overlay | FPS; bitrate; network/decode latency; dropped frames; active decoder; optional authenticated Vibepollo CPU/GPU/RAM/temperature stats; position/opacity; compact/detail views; user-controlled polling |
| Power | Battery saver/performance presets; idle timeout; low-battery notification; lid action; suspend only on validated hardware; restart/shutdown confirmation; charging status; estimated runtime only where reliable |
| Appearance | Existing accent palette/custom accent; black/crimson default; compact/comfortable spacing; text size; reduced motion; optional transparency with opaque fallback; animation intensity; clock format; focus visibility |
| Profiles | Gaming/desktop/low bandwidth/battery/headphones; per-host/app profiles; duplicate/reset/import/export; explicit precedence; show active profile; reversible temporary overrides |
| Recovery | Restart frontend; switch frontend; diagnostic shell; reset display/input/audio separately; restore defaults selectively; support report with credential redaction; logs on demand; previous-image recovery instructions |
| Updates | EclipseOS-owned channel; installed source/version; release notes; stable/experimental labels; manual image instructions; rollback plan; future signed custom-app updates only after compatibility review |
| Accessibility | Larger text; high contrast; reduced motion; accessible labels; keyboard/gamepad focus; readable errors; remappable shortcuts; scalable hit targets; no color-only status indicators |
| Setup | English default; first-run network/audio/host wizard; suggested native display scale; controller pairing help; Mac shortcut guide; optional skip; preserve existing preferences |
| Notifications | Pair/connect/disconnect results; low battery; host unavailable; optional update notice; transient toasts; do-not-disturb during streams; bounded history |
| Diagnostics | Adapter/device names; decoder capabilities; render node; network route; audio sink; Bluetooth state; input test; export a small redacted report; no constant diagnostic polling |
| Convenience | Clock; screenshot shortcut; shortcut help; remember selection; optional on-screen keyboard; quick stream disconnect; session duration; clear connection status |

## Suggested sequence

1. Finish and validate Wi-Fi/Bluetooth selectors and preserve CLI recovery.
2. Add compact control center: audio, brightness, battery, network and power.
3. Correct scaling, pointer defaults, English and Mac shortcut behavior across frontend and streaming.
4. Add profiles, host management and targeted recovery controls.
5. Add optional overlays, diagnostics and visual polish.
6. Measure package/runtime costs before deciding which optional features belong in minimal images.

## Lightweight design rules

Reuse NetworkManager, BlueZ, PipeWire and existing hardware helpers. Start scans and helper processes only when panels open; stop them on close. Poll host stats only while requested. Avoid a bundled browser or full desktop solely for settings. Bound caches, logs and result lists. Keep animation GPU cost modest and support reduced motion. Measure image size, idle RAM/CPU, startup time and streaming latency before and after each meaningful addition.

Every feature should handle unsupported hardware gracefully, remain usable offline where relevant, preserve pairing/preferences, and have a recovery path. Package removal and Mac/generic divergence remain separate future work.
