# Current System Controls verification

Local source checks pass: generated payload parity, installer shell syntax, six bulk BlueZ fixtures, seventeen control-center fixtures, six connection fixtures and the real PTY Bluetooth/frontend audit. Sixteen focused Qt tests pass, including all sixteen exact UI/overlay accent colors, rounded overlay alpha, live scan progress, missing sensors, CPU/network resets and duplicate DRM descriptor handling. Cancel and No dialog actions are exercised through the themed footer; dialog sizing warnings were corrected. Panels were rendered at 100%, 110% and 125% text size and inspected at 1024×640.

Full Fedora compilation, installed-image inspection and OVMF checks for this update are pending. No new image has been claimed ready. See [System Controls](SYSTEM_CONTROLS.md) for behavior and physical acceptance limits.

---

# Eclipse verification record

Runtime source: `0653e04e3312f81b33cb80f879e1badba6aae3b6`.
[Final-source audit](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37095082840): all seven jobs passed.
Candidate build source: `3625507be0a9ca08996ef9a188326c69e7b040fb` (only the controlled build marker changed).
[Candidate build](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37095761480): running; installed-image and boot results are not yet claimed.

This record distinguishes source/fixture evidence, installed-image evidence, generic UEFI boot evidence and physical Mac results. A green fixture test does not establish that every physical device works.

## Pass 1 — source and behavior

Static validation, embedded-payload parity and generated Bash syntax pass. Six connection-helper tests and twelve control-center tests pass. GPU fixtures distinguish hardware decode from encode-only and failed acceleration; all seven media-key actions, releases and repeated mute events pass.

| Area | Reviewed behavior and evidence |
| --- | --- |
| Wi-Fi | Listed-device validation, escaped SSIDs/BSSIDs, scan/connect/disconnect, credentials through a private pipe, bounded timeout and helper cleanup. Hidden/enterprise networks remain a diagnostic-shell task. |
| Bluetooth | Scan/pair/connect/disconnect; explicit confirmation before forgetting; saved bonds preserved on failed pairing; helper/agent cleanup. |
| Audio | Audio-only sink enumeration, output selection limited to listed IDs, volume capped at 100%, mute toggle, unavailable controls disabled. Video sinks are excluded. |
| Brightness | Discovered devices only; screen minimum enforced at 5% by the backend as well as the UI; keyboard lighting may be off. |
| Host tools | Selected host carried from the host/app views, existing Wake-on-LAN method, stats token/TLS checks. Host management stays disabled on the browser-free appliance. |
| Profiles | Host/global isolation, bounded resolution/FPS/bitrate, explicit apply for the next stream, persistence in the existing settings namespace. Codecs/HDR/decoder preferences are not changed by profiles. |
| Appearance | Sixteen accent indices, shared dark tokens, text-size bounds, contrast preference and reduced motion. New buttons use the same outline and radius style. |
| Reports | Bounded/redacted report fields, mode 0600, no device names or credentials, symlink refusal. |
| Power | Restart/shutdown require a boolean confirmation. Suspend is unsupported. |
| Updates | Customized client cannot replace itself with an upstream standalone download; matching OS release guidance is retained. |
| Branding | Eclipse app/window resources, welcome/About text, creator credit, Steam assets, desktop entry/icons and Pegasus label. Internal executable, desktop ID and settings namespace remain compatible. |
| Hardware/recovery | Forty-four other installer heredoc payloads are byte-identical to the preceding Eclipse baseline, including hardware and recovery policies. No minimization or driver removal. |

## Pass 2 — compile and render

Twelve focused Qt tests pass, including all eight required SVG resources decoded through Qt, private helper pipe, managed updater, profile isolation, local/host stats, TLS/authentication, palette and QML panel rendering. Final-source previews were inspected for About, control center, Wi-Fi, Bluetooth, network, battery and host panels. Missing-image warnings and the power-dialog sizing loop were corrected.

The full Fedora job compiles the pinned frontends, checks FFmpeg/VA-API/EGL feature probes and dependencies, verifies installed icon parity and checks GUI startup and Bluetooth fixtures. Separate jobs compile Cirrus against the exact kernel, validate real GPT/XFS growth, verify UEFI tools, and execute the native Plymouth engine at 320×200 through 2560×1600 with prompts and resize hooks.

## Pass 3 — installed image

The candidate inspector passed checks for GPT/ESP/boot/XFS layout, removable EFI boot path, exact kernel/initramfs/modules, selected Plymouth theme and initramfs assets, all clients/helpers, desktop/icon/launcher branding, exact helper and patch bytes, source pins, enabled services, Intel nonfree iHD, SBC/AAC plugins, input/network/audio policies and recovery tools. Icon PNG headers and all three installed dimensions passed. Image size is within the conservative 16 GB drive target.

## Pass 4 — UEFI boot and artifact

The candidate booted through OVMF and satisfied the required `MOONLIGHT_OS_BOOT_OK`. Validation uses a disposable qcow2 overlay; the release image is not modified. Compression and upload completed after successful inspection and boot. The artifact contains one `.img.xz` plus its basename-compatible SHA-256 file. Existing published regular/experimental links remain intact.

## Physical acceptance still required

- Native-resolution launcher scaling, every panel and scroll area, keyboard/controller focus, Enter/Escape and Ctrl+Shift+C.
- Real Wi-Fi password failures/retry, network persistence, Bluetooth PIN/confirmation flows, paired-device persistence and adapter recovery.
- Internal speakers/mute/output selection; AirPods Pro 2 playback, mode switching and measured latency; DualSense HID with its audio endpoints suppressed.
- Screen/keyboard brightness and all media keys before/during streaming, including mute.
- Real i915/VA-API H.264/HEVC decode telemetry, mouse/keyboard/trackpad/controller behavior, sustained streaming and reconnect.
- Saved profiles/appearance across reboot, actual host-stat compatibility, battery/thermal behavior, redacted report export, confirmed restart/shutdown and recovery console.

OVMF proves generic x86_64 UEFI boot only. It does not establish Mac-specific hardware operation or streaming latency. Optional roadmap items in `VIBEMIS_FEATURE_PLAN.md` are not claimed as shipped.
