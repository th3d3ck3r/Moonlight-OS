# 🖤🔴 Crimson Console — self-contained Moonlight-OS implementation plan

**Status: plan only; not implemented.** Created October 2, 2026.
**Current request: write this plan without implementing it or starting an image build.**

## Execution contract for a future session

When the user explicitly asks to execute this file, implement the terminal settings interface directly in **https://github.com/th3d3ck3r/Moonlight-OS**, preserve existing features, run focused audits, and commit/push the source changes. **Do not launch an image build, change `.github/BUILD_ONCE`, or dispatch the build workflow under this prompt.** A later explicit build request is required. Do not cancel an unrelated repair build already running.

Read `BUILD_STATUS.md`, `SOURCES.lock`, `config/moonlight-os.ks`, `scripts/validate.sh`, `scripts/audit-runtime.py`, and `docs/TEST_PLAN.md` first. Inspect current `main` and Actions history. Use `CODEX_BUILD_PROMPT.md` only to understand preserved invariants; do not execute its build sequence. `docs/HOST_OVERLAY_PLAN.md` and `docs/LIQUID_GLASS_GUI_PLAN.md` are independent projects, not implementation dependencies. Do not merge or implement them through this plan.

Suggested future invocation:

> Read CODEX_CLI_INTERFACE_PROMPT.md in this repository and execute its instructions. Work directly in my existing GitHub repository, preserve existing features, use my remaining usage efficiently, quadruple-check the changes, and commit and push all fixes. Do not start a new image build.

## Product goal and visual direction

Replace the plain numbered `moonlight-settings` menu on **tty2** with a polished, fast **terminal user interface (TUI)**. Keep `moonlight-settings` as its entry command and retain a working plain-text menu and diagnostic shell as recovery paths. CocoOS remains the default streaming frontend, with upstream Moonlight as fallback. This is a settings console, not a replacement graphical streaming client.

Use a predominantly black canvas, deep-crimson selected panels, bright-red focus markers and a small monochrome Moonlight title. Near-white primary text and gray secondary text keep settings readable. Use compact status chips, tidy borders, consistent spacing, sliders, toggles, searchable lists and a persistent key legend. No constant animation, blur, compositor or full desktop. Emoji belong in documentation; console icons must have text/ASCII fallbacks because Linux-console fonts may not contain them.

| Element | Design target |
| --- | --- |
| Canvas / panels | Black; very dark neutral panel separation |
| Selection | Deep crimson background, bold readable label, explicit selection marker |
| Focus / actions | Red highlight plus shape/text, never color alone |
| Reading text | Near white; muted gray for explanations and disabled controls |
| Errors | Clearly labeled error panel; decorative red must not hide error meaning |
| Layout | Header/status, category navigation, settings/detail pane, footer/help |
| Small terminal | Single-pane list with breadcrumbs; no clipping or horizontal scrolling required |
| Motion | None by default; bounded refresh only for visible status |

Treat hex colors as design targets rather than promises about tty color depth. Support the Linux console's limited palette, 16/256-color terminals, monochrome/high contrast, and terminals without Unicode. Do not repaint the streaming X11 session or permanently overwrite the recovery-console palette.

## Navigation and interaction

Keyboard first: arrows move; Tab switches panes; Enter opens/applies; Space toggles; Escape backs out; `/` searches settings; `?` opens help. Show shortcuts on screen and provide ordinary-key alternatives to function keys. Preserve Mac **Control + Option + F1/F2** console switching, adding Fn when needed, and **Control + Option + Shift + M** stream mouse-mode switching. Do not intercept brightness, keyboard-light or volume keys away from the existing media-key service.

Show current value, allowed range, brief explanation, scope (**local device / stream / host**), persistence, and whether a change applies **now / next stream / next client launch / next boot**. Use Apply/Cancel for edits; confirm disconnect, unpair/forget, client restart and power actions. Offer restore-last-good settings. Never display a fake successful result after a command fails.

## Settings inventory — discover capabilities before enabling controls

These are required settings areas, not a claim that every device or pinned client supports every field. Inventory the exact pinned clients' `StreamingPreferences`, QSettings keys/enums and hardware capabilities first. Controls must be **editable**, **read-only**, or **unavailable with a reason**. Preserve existing defaults unless the user changes them. Unsupported combinations must not silently fall back to software decoding.

| Area | Settings and actions |
| --- | --- |
| 🏠 Overview | Selected frontend, host reachability, Wi-Fi connection/signal, audio output/volume, panel mode, brightness, battery/charging, active stream indicator and concise health warnings |
| 🎮 Client / hosts | CocoOS or upstream Moonlight selection; apply at next launch or explicitly restart; discovery/mDNS where supported; host list/manual address, pairing/re-pairing/forget with confirmation; app refresh and launch using verified existing client interfaces |
| 📺 Stream video | Resolution/custom dimensions/aspect ratio, FPS, bitrate and supported automatic adjustment, VSync/frame pacing, codec Auto/H.264/HEVC, decoder/renderer selection, fullscreen/window mode, performance overlay, connection/configuration warnings, game optimizations and quit-after-stream options when present |
| 🖥️ Local display | Detected output and native mode; supported resolution/refresh choices, app UI scaling/text size, console font/readability, screen brightness, blanking/keep-awake settings; distinguish local panel settings from remote stream resolution and host desktop scaling |
| 🖱️ Mouse / trackpad | Direct desktop versus captured game pointer explanation/toggle, supported client mouse options, local speed/acceleration separately, tap-to-click, clickfinger/right-click, natural scrolling, left-handed buttons and touch options where exposed |
| ⌨️ Keyboard | Keyboard layout and available locale, English default, function/media-key behavior where the driver supports it, keyboard-light level and persistence, shortcut reference and a non-recording key test; preserve local media-key operation during capture |
| 🔊 Audio | Output-device selection, volume/mute capped at 100% by default, output test, hardware mixer with save/restore, per-device saved levels where reliable, stream audio channel configuration, host audio playback, mute-on-focus-loss where supported; clearly separate PipeWire volume from ALSA hardware gain |
| 🎧 Bluetooth / AirPods | Power/scan/pair/connect/disconnect/trust/forget, connection/battery information when exposed, playback output selection, existing Low Latency/Quality preference, negotiated codec/status and reconnection troubleshooting |
| 🕹️ Controllers | DualSense USB/Bluetooth status and pairing; multiple controllers, button-layout swap, gamepad mouse, background input and mappings where supported; vibration/deadzone options only when backed by an actual client setting; controller test without enabling its audio endpoints |
| 📶 Wi-Fi / network | Scan/connect/saved profiles, masked credentials, reconnect/forget, radio/rfkill state, 5 GHz preference/automatic band, signal/link details, IP/DNS/gateway, DHCP or validated static addressing, diagnostic ping to selected host, bounded latency/loss tests; show wired options only when an adapter exists |
| 🔋 Power / thermals | Battery/charging/time estimate when available, temperatures/fan status when exposed, thermald status, supported power policy, idle/blanking/suspend preferences, keep-awake during streams, explicit reboot/shutdown; do not promise fan control or undervolting |
| 🩺 Diagnostics | Hardware verifier, matched i915/render node, VA-API H.264/HEVC **VLD** capabilities, OpenGL renderer/software-render warnings, video-engine telemetry, input/audio/Bluetooth/network checks, service status, bounded relevant logs and sanitized support bundle |
| 💾 Storage / persistence | Boot-USB identity, free space, growth-service result, saved setting location, configuration backup/export/import and reset by category; no installer, repartition action or internal-Mac-SSD write |
| 🛠️ Advanced / recovery | Client launch logs, retry/fallback status, module/package versions, read-only build/source information, settings schema/version, plain-menu fallback, diagnostic shell and recovery of last-good settings; no unattended distro/kernel upgrade |
| ♿ Help / accessibility | Search, category help, Mac shortcut cheat sheet, larger console text, high contrast/monochrome, reduced refresh, keyboard-only navigation and explanation of unavailable controls |

Special capability rules:

- This Mac's native panel was observed as **eDP-1, 2560×1600**; detect outputs rather than globally hardcoding that name. Keep native mode as the baseline. A remote Windows desktop's scale is a host setting; changing local Qt UI scale must not rewrite it.
- Iris Plus 640 H.264/HEVC decode is confirmed at capability level with the full `intel-media-driver`. Do not claim hardware AV1, HDR or 4:4:4 support from a visible toggle alone. Disable unsupported hardware paths and explain the limitation; keep software decode an explicit diagnostic choice, not an automatic hidden fallback.
- Preserve AirPods playback-only A2DP policy. Latency/Quality is a preference, not a guaranteed codec or latency figure. Do not enable HSP/HFP microphone roles through this menu.
- Preserve disabled DualSense audio endpoints and functioning HID controls. Never offer an “enable controller audio” toggle.
- Host dashboard and remote hardware statistics belong to `docs/HOST_OVERLAY_PLAN.md`. The console can reserve a future integration point, but must not add new host API authentication, remote telemetry polling or arbitrary remote execution in this project. A running streaming host cannot be started remotely without an independently supported mechanism; do not promise it.
- Updates, SSH enablement, firmware installation and host management are not unrestricted convenience actions. Retain current SSH-disabled and camera-firmware policies. Show versions/status and documented maintenance instructions instead of implementing broad system mutation.

## Implementation approach

1. **Inventory and map.** Produce a setting-to-backend matrix from the current helpers and both pinned clients. Inspect actual preferences/key names separately for CocoOS and Moonlight. Record unsupported settings and restart requirements. Do not assume the clients share a writable configuration format.
2. **Build a small TUI shell.** Prefer Python 3 plus the standard curses interface if verified on Fedora 44. Reuse installed tools; add a dependency only if a small audit proves it necessary. Use an unprivileged frontend, a screen model, a capability layer and explicit backend adapters. Keep rendering separate from state changes.
3. **Connect existing operations first.** Delegate Wi-Fi/Bluetooth/AirPods/client selection/audio/diagnostics to the existing helpers or verified structured command APIs. Preserve `moonlight-settings-plain`. Suspend curses correctly before launching `alsamixer`, `nmtui`, `bluetoothctl` or a diagnostic shell, then restore it after exit.
4. **Add validated editing.** Use argument arrays, no shell evaluation of user text, bounded timeouts, captured exit status and strict ranges/enums. Do not run the whole interface as root. Privileged changes go through narrow, explicit adapters using the project's existing authorization model. Never log Wi-Fi passwords or pairing secrets.
5. **Handle running clients safely.** Do not write Qt preference files concurrently with a client that can overwrite them. Use a verified existing runtime interface when available; otherwise defer writes until clean client exit or explain that a restart is required. Back up targeted client configuration before editing and preserve unknown keys.
6. **Persist deliberately.** Version the TUI's own configuration, validate imported data, save atomically on the boot USB, separate device-specific values from portable preferences, and keep credentials out of exports by default. Apply category resets without wiping pairing/network credentials or changing source pins.
7. **Guard disruptive changes.** Queue X11 mode changes for the active graphical VT; do not blindly run xrandr from inactive tty2, where CRTC failure was observed. Provide a timed rollback to the detected last-good mode even if the TUI crashes. Explain network disruption before reconnect/static-IP changes and preserve the current working profile.
8. **Package and document.** Install through the existing Kickstart; keep tty2 entry and tty1 client startup/fallback intact. Add focused audit coverage, a setting/backend matrix, screenshots from a real terminal, and usage/recovery instructions. Commit and push source changes without triggering an image build.

## Preserve the physical fixes and previous features

Keep Openbox startup before either client, native-resolution/fullscreen handling, the checked English CocoOS source translation, the full Intel driver, dynamic i915/render-node discovery and VLD verification. Preserve the console readability setting (`stty rows 100` on the tested Mac), SPI keyboard lighting, the media-key service, and explicit hardware mixer save/restore. The user confirmed screen brightness, keyboard brightness and volume keys; preserve those actions exactly until a demonstrated problem warrants a change.

The TUI must handle terminal resizing/font changes using real geometry; `stty` dimensions alone do not change framebuffer resolution or fix every terminal. Do not hardcode 100 rows for all machines, render below the visible screen or replace the working console font with one that hides the prompt.

Keep native X11 without a compositor/full desktop, hardware decode/diagnostic requirements, source/kernel pins, Cirrus GCC16 fixes, BCM4350 latency policies, Bluetooth/AirPods rules, DualSense HID/audio rules, disabled SSH, safe GPT/XFS growth, live-USB operation and the 14,000 MiB image limit. Do not access the internal SSD. Keep diagnostics available on failures and both other feature plans unchanged.

## Four review passes — efficient source validation, no new image

1. **Structure/UI:** parse/compile checks, focused terminal tests, resize and small-screen navigation, color/Unicode fallbacks, ordinary-key navigation, clean signal/exception exit, terminal restoration and usable recovery menu/shell.
2. **Backends/config:** test actual command arguments, ranges/enums, capability gating, failure messages, timeout/disconnect handling, secret masking, atomic save/import/reset, adapter differences and client configuration concurrency. Use disposable profiles/configuration and mocked hardware for destructive cases.
3. **Feature regression:** verify every original setting/helper remains reachable, media keys still work with the TUI and stream capture, native display rollback works, both clients/fallback remain intact, and audio/AirPods/DualSense/input/network policies are unchanged. Check CPU/polling behavior: bounded visible-screen refresh, no busy loop or telemetry work while the TUI is closed.
4. **Integration/delivery:** run current static/runtime audits and only relevant Fedora/package audits; inspect generated Kickstart payload paths, units and required tools. Compare source pins and independent plans. Report actual physical checks separately from fixtures. **Do not claim a newly boot-validated image or start an OVMF/image build under this prompt.** Mark source ready for a separately authorized build.

Run a focused test once it passes; broaden/repeat only after a meaningful change or failure. Read exact CI errors before editing. Avoid full client recompilation for a terminal color/layout change. Do not run the expensive Cirrus audit when its inputs remain unchanged unless repository policy requires it. Do not weaken existing CI or delete diagnostics to save usage.

## Acceptance and handoff

Done when the terminal interface is coherent in black/crimson, all listed settings have honest capability/apply-state handling, working settings persist correctly, recovery remains usable, relevant audits pass, regressions are addressed, and source/documentation are committed and pushed. Unsupported controls must show a clear reason rather than pretend to work.

Report implemented/editable versus read-only/unavailable settings, test evidence, physical checks still needed and the commit. **No new disk image is part of this plan's execution.** A future explicitly authorized image build must still inspect the installed payload and pass the existing strict OVMF boot gate before publishing a download.
