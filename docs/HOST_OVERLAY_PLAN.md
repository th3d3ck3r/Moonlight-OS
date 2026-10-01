# 🎮 Host stats overlay & dashboard — implementation plan

Status: planned, not implemented. Prepared October 1, 2026.
Start implementation after the current USB image boots on MacBookPro14,1 and passes basic GPU/input/network/streaming checks. Keep the validated v0.1 artifact as the baseline.

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

Use the existing native streaming overlay, with modes **Off → Client → Host → Both**. Preserve ordinary Off/Client toggling when host stats are not configured. Provide a mode selector in each client's settings, and reuse existing stats keyboard/controller actions to cycle available modes after configuration. Display the actual binding in help; do not introduce conflicting Start-long-press or quit combinations.

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
2. **Create shared patch sources.** Store reviewed patches in Moonlight-OS for the exact two pinned client commits. Apply them after checkout and before qmake in Kickstart. Include new Qt network sources/headers in `app/app.pro`. Fail builds when a patch no longer applies; do not edit an external upstream branch or advance source/kernel pins casually.
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
