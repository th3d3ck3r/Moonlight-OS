# 🎮 Host stats overlay & dashboard — implementation plan

**Current baseline:** [experimental release](https://github.com/th3d3ck3r/Moonlight-OS/releases/tag/v0.1-experimental.20261002) adds five frontend choices (initial default/fallback Moonlight), generic Bluetooth and Crimson Apollo. This plan remains independent and unimplemented; preserve all five choices and their existing settings. Earlier source findings below apply to the inspected CocoOS/Moonlight revisions, not automatically to the added forks.
Status: planned, not implemented. Prepared October 1, 2026.
Start implementation after the current USB image boots on MacBookPro14,1 and passes basic GPU/input/network/streaming checks. Keep the validated v0.1 artifact as the baseline.

## Independent scope

This plan implements only the optional host-stats overlay and dashboard button. It does not implement the Crimson Glass redesign. Preserve the existing interface and standard streaming behavior unless a change is explicitly required here.

## Verified source findings

Inspected these exact revisions:

| Project | Revision |
| --- | --- |
| Nonary/Vibepollo | `8a8c4b03a280ab9f567beb380110abb80f5220b8` |
| Djingerr/CocoOS | `8c22132f1ce4146c0d6bff812f6fc8f724fe0101` |
| moonlight-stream/moonlight-qt | `8369d1a0e11b999d4d1598f62ca5f6dea49602fb` |

Vibepollo's [confighttp.cpp](https://github.com/Nonary/Vibepollo/blob/8a8c4b03a280ab9f567beb380110abb80f5220b8/src/confighttp.cpp) registers authenticated GET endpoints:

- `/api/host/stats`: CPU/GPU percentages and temperatures, RAM/VRAM used/total/percent, GPU encoder percent, network receive/transmit rates.
- `/api/host/info`: CPU/GPU names, logical cores, memory totals, interface name, link speed.
- `/api/rtsp/sessions`: separate stream session counters, including encode latency. Defer this endpoint to a later extension; host encoder utilization is not encode latency or game FPS.

The API lives on the HTTPS configuration/web interface server. Default base port is 47989 and configuration HTTPS uses offset +1, giving 47990; permit a per-host override.

[http_auth.cpp](https://github.com/Nonary/Vibepollo/blob/8a8c4b03a280ab9f567beb380110abb80f5220b8/src/http_auth.cpp) supports `Authorization: Bearer <token>` and path/method scopes. The stats endpoints authenticate independently of GameStream pairing. Do not assume a paired Moonlight client already has management API access.

[host_stats.cpp](https://github.com/Nonary/Vibepollo/blob/8a8c4b03a280ab9f567beb380110abb80f5220b8/src/host_stats.cpp) gates sampling on `realtime_stats_enabled` and clamps configured sampling intervals to 250–60000 ms. The host's installed version must be checked: inspection of current source does not prove those endpoints exist in the user's build.

Both pinned clients have identical `app/streaming/video/overlaymanager.{h,cpp}` implementations, existing stats keyboard/controller controls, and stats formatting in `app/streaming/video/ffmpeg.cpp`. Session streaming temporarily takes over the main thread's Qt event processing.

Renderers currently recognize only debug and status overlays; the EGL renderer asserts on an unknown overlay type. Avoid adding a third overlay enum in the first version.

## User-facing behavior

### Toggleable stats

Use the existing native streaming overlay, with modes **Off / Client / Host / Both** selectable from settings. Preserve existing client-stats keyboard/controller actions and their Off/Client behavior unchanged. Add a separate configurable host-stats toggle only after checking keyboard/controller conflicts, with clear help and debounce/release handling. Do not repurpose Start-long-press, quit, mouse-mode or original stats combinations.

Initial host panel:

- CPU utilization / temperature
- GPU utilization / temperature / encoder utilization
- RAM and VRAM usage
- Network receive/transmit rate
- Clear **HOST** and **CLIENT** labels in combined mode

Compact outlined text first. No separate overlay window, desktop environment, compositor, or changes to hardware decoding. Unsupported values display **N/A**, not 0. Negative unavailable sentinels, invalid numbers, missing fields and zero totals require explicit handling. No game FPS claim unless a separate verified source supplies it.

Refresh every **2 seconds** while Host/Both is visible. Pause requests in Off/Client, between sessions, and on exit. Show “Host stats unavailable” or “Disconnected” without interrupting a stream. The endpoint has no sample timestamp, so label local receipt freshness accurately rather than implying the host produced a new sample.

### 🌐 Open Host Dashboard button

Interpret “launch the host” as opening the selected host's **Vibepollo/Sunshine management web page**, not powering on the PC or starting its service.

Add **Open Host Dashboard** to CocoOS host options and upstream Moonlight's host context menu. Use a controller-navigable button with the selected host's name. Open `https://<host>:<configured-web-port>/`; default 47990, IPv6-safe URL construction, and an editable per-host address/port.

The current appliance installs no browser. Merely calling `QDesktopServices::openUrl` would therefore be incomplete. Evaluate a Fedora-packaged browser (Firefox is the initial candidate), launch through a dedicated helper as the unprivileged `moonlight` user in the existing X11 session, and return focus to the client when it closes. Measure its installed footprint before accepting it.

For version one, offer dashboard access **before streaming**; during streaming, require the session to end before opening it. This avoids stealing fullscreen input or running a browser alongside a latency-sensitive session. Keyboard/mouse are required to administer the web page; controller navigation to the button does not imply controller navigation through arbitrary web content.

Dashboard login stays in the browser. Do not insert API tokens into URLs or use the read-only stats token to log into the management page. Handle self-signed certificates through explicit trust confirmation and host-specific pinning where implemented; never disable HTTPS validation globally.

If adding a browser exceeds the **14,000 MiB raw / 16 GB USB** requirement, stop and revise the package budget before rebuilding. Keep necessary hardware drivers and diagnostics; do not silently exceed the limit.

Wake-on-LAN and starting a stopped Sunshine/Vibepollo service are separate features, outside this first plan.

## Implementation steps

1. **Confirm physical baseline.** Boot USB; verify Intel acceleration, keyboard/trackpad, networking and a real stream. Record overlay-off latency/frame pacing. Establish actual host version, HTTPS URL, stats setting, endpoint responses and available sensors.
2. **Create shared patch sources.** Store reviewed patches in EclipseOS for the exact two pinned client commits. Apply them after checkout and before qmake in Kickstart. Include new Qt network sources/headers in `app/app.pro`. Fail builds when a patch no longer applies; do not edit an external upstream branch or advance source/kernel pins casually.
3. **Add telemetry model/worker.** A dedicated QThread with its own event loop owns QNetworkAccessManager and QTimer. Transfer immutable snapshots through a bounded, synchronized mailbox; render/video threads never perform HTTP. One request in flight, timeout around 3 seconds, bounded response size, safe redirects (never forward credentials across origins), backoff on errors, cancellation on hide/exit, and clean shutdown before Session destruction.
4. **Add per-host setup.** Persist optional management URL, certificate trust/pin, and scoped bearer token. Request only GET access to `/api/host/stats` and `/api/host/info`. Store token outside general settings/logs in a user-only file with mode 0600; USB persistence is not encrypted storage. Keep tokens out of process arguments, diagnostics and crash output. Cache host info; refresh on explicit reconfiguration/reconnect.
5. **Compose the overlay.** Extend the existing debug overlay formatter to choose Client/Host/Both. Copy the latest snapshot under a short lock; update the overlay through its existing producer path rather than calling the font renderer from the network worker. Account for the 1024-byte text buffer: bounded composition/truncation or a tested buffer increase. Keep the status overlay free for connection and mouse-mode warnings.
6. **Add controls and dashboard helper.** Implement settings for both front ends, keyboard/controller mode cycling with debounce and release handling, accessible help text, host-menu button, browser process lifecycle/focus restoration, and explicit unavailable/offline feedback. Browser opens only the configured host HTTPS address.
7. **Extend build/inspection checks.** Ensure both binaries contain the feature, shared patches are reproducible, and dashboard browser/helper dependencies exist. Add patch inputs to `out/build-inputs.sha256` recovery manifests so a changed client payload cannot reuse a stale raw image.
8. **Validate before another release.** Run targeted client tests/audits first. Build one fresh image once checks pass; require inspection and OVMF again, then repeat physical Mac streaming tests.

## Acceptance tests

| Area | Required result |
| --- | --- |
| API contract | Parse realistic snapshots, absent fields, negative sentinels, zero totals, invalid JSON, oversized responses and unexpected units without crashes |
| Authentication/TLS | Valid scoped token works; 401/403/404, revoked token, offline host, changed certificate and cross-host redirect fail safely |
| Compatibility | Ordinary Sunshine lacking these endpoints streams normally; optional stats report unsupported |
| Thread/lifecycle | Requests continue during SDL streaming; no network calls on render thread; no overlapping requests or use-after-free on disconnect/reconnect/exit |
| Visibility | Off/Client stops stats polling; Host/Both resumes; mode cycling is debounced; controller inputs do not remain stuck |
| Rendering | Both clients, hardware H.264/HEVC, fullscreen/windowed and tested scaling; warnings remain visible; host/client labels and N/A are correct |
| Dashboard | Selected host URL and custom port correct; browser launches as user; login/certificate flow works; closing returns to client; offline host handled |
| Performance | Compare overlay off/on at matched stream settings; retain Intel hardware decode and no reproducible added stutter; record CPU, decode/render timing and dropped frames |
| Image | Under 14,000 MiB raw, all existing hardware/audio policies intact, read-only inspection and OVMF marker pass |
| Stability | 30-minute stream, repeated toggle, host restart, token revocation, client switching and multiple reconnects |

Later enhancement: small graphs and a five-minute local history buffer, after text telemetry is stable and measured. At two-second polling, 150 samples per series is sufficient; record gaps when hidden rather than continuously polling just to fill graphs.

## Delivery boundary

This document is a plan only. No client patches, browser packages, API credentials, kernel changes or image builds are introduced by this planning commit. Implementation begins after the user's physical boot report.

## Feature preservation — required for this plan

Scope: optional telemetry and dashboard only. The following checks preserve the existing OS and clients; they do not authorize the other feature plan.

| Existing requirement | Required preservation check |
| --- | --- |
| Fedora 44 x86_64; source/ISO/kernel pins | Keep SOURCES.lock pins and compare installed kernel/module alignment; review any necessary change separately |
| Native X11 appliance | No desktop environment, compositor, GNOME/KDE/Gamescope dependency or second streaming UI |
| GPU acceleration | i915 + Intel VA-API H.264/HEVC, EGL/Mesa/libplacebo/FFmpeg/SDL probes; runtime rejects llvmpipe/softpipe |
| Apple/external input | Apple SPI and libinput keyboard/trackpad, USB/Bluetooth keyboard/mouse; preserve original streaming shortcuts, gamepad input and supported haptics |
| BCM4350 networking | brcmfmac, Wi-Fi power saving disabled and roamoff=1; NetworkManager helpers and persistent saved networks |
| Bluetooth | Existing pairing, trust/reconnect and persistence; absent hardware/timeouts do not break boot or streaming |
| DualSense | hid-playstation over USB/Bluetooth; suppress only controller audio endpoints and preserve HID |
| AirPods Pro 2 | Playback-only A2DP, no HSP/HFP or microphone switching; Low Latency/Quality switch and installed SBC/AAC codec checks |
| Internal audio | PipeWire/WirePlumber + pinned Cirrus DKMS module for exact installed kernel; keep the GCC16 workaround |
| Clients/protocol | remembered five-way selector, CocoOS embedded build, upstream Moonlight initial default/fallback, standard Sunshine/GameStream pairing/discovery/stream/input; Companion and stats APIs optional |
| Settings/recovery | Ctrl+Alt+F2, original text helpers and red-on-black diagnostics survive graphical setup failure |
| Boot/storage | GPT/ESP/ext4 boot/XFS root, BOOTX64.EFI, safe sysfs-based root growth/NOCHANGE/retry, required service ordering and genuine marker |
| Physical disk safety | Never write/mount internal SSD as part of live-USB feature setup; no auto-install or partition migration |
| Power/accessibility | Retain thermald, brightness/battery tools, USB-C/Thunderbolt/storage diagnostics and existing kernel command-line policy |
| Development/support | Retain compiler/source/DKMS/debug tools; SSH stays disabled; no FaceTime firmware added |
| Capacity | Less than 14,000 MiB raw on a 16 GB-or-larger USB; measure browser, QML/effect and asset costs |
| Validation/recovery | Do not weaken installed checks or OVMF; changed client/asset inputs invalidate recovered raw manifests |

Features must degrade independently: stats off or unavailable cannot block streaming; a browser failure cannot restart the client loop indefinitely; theme failure has an opaque/basic UI escape route; text recovery remains independent. Implement documented safe settings/launcher overrides before enabling replacements by default, and test recovery rather than assuming it exists.

Existing settings and per-host pairing records must load unchanged. New settings get versioned defaults and atomic writes; migration makes a backup and never deletes network/Bluetooth/client data. Preserve all current stream options, including advanced options not highlighted in the new GUI.

## Four review passes before authorizing a full image build

**1 — structure and contract.** Inspect actual changed diff; shell/embedded heredoc syntax, Kickstart/ksvalidator, units/order, QML imports/resources, source pins, patch application on both exact client commits, settings compatibility, shortcut conflicts, workflow triggers and documentation. Keep static validators intact. Build trigger is still controlled; no trigger-file edit during planning.

**2 — packages and client behavior.** Run the smallest changed-feature tests first: bounded API parser/auth/TLS/timeouts, lifecycle/thread ownership, overlay rendering/input, QML navigation/English/layout and settings failure paths. Validate new Fedora packages/imports/shader tooling, accelerated configuration and both patched client builds. Run all six repository audits (static, Fedora/frontends, audio, image-tools, root-growth, boot-animation) on the final candidate. Keep Cirrus/source checks even if feature code does not touch them.

**3 — regression and resource review.** Compare the invariant matrix above with the candidate source/package/asset manifest. Check both clients and disabled-feature paths; exercise state migration and recovery. Measure browser/effect resource impact and preserve the raw size budget. Obtain the physical baseline boot/stream report. Use isolated client builds/previews for feature and performance verification before rebuilding the OS.

**4 — integration and release readiness.** Verify offline first-boot behavior, graphical settings failover, session/browser lifecycle, credentials handling, root-growth/service dependencies and genuine boot-marker behavior. No network API or browser readiness condition may become a prerequisite for boot success. Confirm prior targeted/full audit results match the exact candidate and that no unreviewed edits remain. Then permit one fresh image build.

After that single build, mandatory installed-image inspection validates actual partitions, kernel/initramfs, both clients, resources/dependencies, all hardware modules/policies and helper/services. OVMF must emit the real marker through a qcow2 overlay before artifact compression/upload. These image/boot checks necessarily happen after creating the candidate image; never claim they passed from a pre-build document review.

OVMF still proves generic UEFI, not the physical MacBook. Repeat real hardware tests, matched overlay/theme off/on streams, controller/audio checks and persistence before calling the feature release hardware-validated.

## Usage and CI efficiency

- Reuse inspected source revisions and verified logs; do not re-research solved audio/GPU/UEFI work without new evidence.
- Batch related edits into one reviewable commit; avoid multiple pushes that cancel/restart the same full audit.
- Documentation-only planning changes do not justify a full image build. The existing audit workflow may still run on push; leave its protections intact and inspect the relevant result.
- Preview UI locally and build only the changed client/component while iterating. Patch-application probes alone are not a substitute for final client compilation.
- Use API fixtures/mock responses for offline/auth/malformed-data tests; use an actual host only for contract and end-to-end checks.
- No full OS image build for color/layout/string/API-parser fixes that a smaller test can establish.
- Final candidate: targeted tests → all six audits → one image build → inspection/OVMF → physical validation. Do not push unrelated edits while that build is running.
- On failure, read the exact saved log, change the smallest demonstrated cause and repeat the applicable checks. Recovery reuse requires matching hashes for every payload input; changed patches, resources or packages require a fresh installed image.
- Save a short checkpoint with candidate SHA, tests, remaining blocker and next command so work can resume without retracing it.


## Review status

Reviewed against CODEX_BUILD_PROMPT.md, current Kickstart, source pins, validation scripts and the physical test plan. Planning changes are documentation only. Compatibility cannot be guaranteed from a plan: the four passes must be executed against implemented code, with actual test results. Physical boot/basic streaming remains the prerequisite, and no full image build is needed for this document review.
