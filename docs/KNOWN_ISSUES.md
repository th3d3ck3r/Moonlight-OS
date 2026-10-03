# Known issues and physical acceptance

These limitations apply to Crimson Glass and the preserved System Controls comparison build. The automated checks establish source, fixture and generic boot behavior; they cannot establish every physical Mac peripheral feature.

| Area | Current limitation / next check |
| --- | --- |
| Bluetooth controller power | The previously tested image had a broken graphical scan and slow pairing followed by controller power-off. The new shared BlueZ backend removes per-device CLI waits and checks service/input readiness, but the controller power-off symptom still requires physical retesting. Wake the device and use Reconnect if its saved bond is present. |
| Adapter firmware | A Mac Bluetooth adapter may still need the documented one-time SMC reset after switching from macOS. Missing adapters and disabled radios are reported explicitly. |
| Hardware sensors | Some Macs/drivers expose no GPU utilization, CPU clock, fan or power counters. Those values show Unavailable. Rates appear after a second sample; USB/root I/O requires an accessible root block device. |
| GPU statistics | Eclipse video-engine activity covers this process only. Total GPU memory is unavailable; Intel shared graphics memory is system RAM. |
| Pointer and idle settings | Apply to the current X11 session; restarting the frontend or rebooting restores startup policy. |
| Display changes | Only advertised modes with a known current rollback mode are offered. A disconnected display or failing X server can prevent rollback; tty2 remains the recovery path. |
| Background selection | Local PNG/JPEG/WebP/BMP images up to 32 MiB are supported. A resized copy survives removal of the original file. Choose the containing folder on a mounted drive; remote URLs are rejected. Very large or corrupt images are rejected. |
| Crimson Glass responsiveness | Side panels collapse on smaller windows; app/host grids remain scrollable. Native overlays are sized independently of UI text scale. No real-time blur or proprietary Apple material is used. |
| Overlay graph semantics | Histories retain 60 samples, not a fixed five-minute duration. FPS comes from rendering stats; network latency is network RTT, not total input-to-photon latency. Missing readings create gaps. Physical sustained streaming and low-resolution fit still need testing. |
| Overlay layout | Native Linux renderers support both cards and corner selection. Detailed overlays at low stream resolutions still need physical review for fit and readability. |
| AirPods | Microphone/headset profiles remain disabled. Actual negotiated codec and latency require physical playback tests. Switching the preference restarts user audio services. |
| Suspend / lid policy | Additional presets remain unavailable pending physical validation. |
| Wi-Fi | Hidden/enterprise networks remain a diagnostic-shell task. |
| Host hardware stats | Require a compatible host endpoint and trusted TLS/authentication configuration. Local Mac monitoring works independently. |
| Build downloads | GitHub Actions artifacts expire. Preserve the documented fallbacks and verify the included SHA-256 before flashing. |

Physical acceptance should cover Bluetooth scan/pair/reconnect across reboot, controller input without unexpected shutdown, audio/media keys, AirPods modes, brightness, display rollback, trackpad settings, all sixteen accents and text sizes, both overlays, sustained hardware-decoded streaming, recovery console and confirmed power actions. OVMF boot does not prove Mac-specific hardware support.
