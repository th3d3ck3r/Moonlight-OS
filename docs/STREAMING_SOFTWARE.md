# Streaming software fixes and renderer investigation

Prepared on `wip/eclipseos-updater`, without building or installing an image/frontend/release package. Physical reports on October 3 show Wi-Fi selector failure, Bluetooth `UnknownMethod`, and a pacing gap compared with Windows. Pacing persists in both windowed and fullscreen. The requested focus is software, drivers and rendering; the kernel/base stay fixed.

## What the stream screenshot establishes

| Measurement | Observed |
| --- | --- |
| Stream | 1920×1080 HEVC, 59.35 FPS |
| Incoming / decoded | Both 59.35 FPS |
| Rendered | 56.54 FPS |
| Network drops | 0.00% |
| Pacing drops | 4.72% of decoded frames |
| Network latency | 2 ms |
| Mean decoding / rendering time | 4.94 / 9.97 ms |
| Hardware decode | HEVC VA-API; Intel iHD driver |
| Pacing worker / presentation mode | `none` / `n/a` |

This snapshot points at client presentation loss, not measured network packet loss. Render time includes V-sync waiting; it is not a pure GPU-work measurement. CPU 18.6% does not exclude a busy individual core. Decoder/render work can overlap, so adding their averages does not establish a pipeline bottleneck.

Source inspection confirms X11 has no dedicated `IVsyncSource` like the Windows path; a requested frame-pacing setting can therefore still report `none`. The drop counter also counts render-queue overflow when that pacing source is absent. `none` does not mean the render queue cannot drop frames or that display synchronization is disabled. Window mode alone does not select a different decoder backend.

The existing overlay's **via VAAPI** names the decoder backend, not the presentation frontend. `present: n/a` does not identify whether EGL or direct VA-API draws the frame. The prepared frontend patch adds a separate bounded **Renderer: ...** line, cached across teardown, so later screenshots can name the actual frontend instead of guessing it.

## Source fixes prepared

- **Bluetooth wire types:** introspection is deliberately disabled. Property setters used `dbus.Boolean(True)`, producing `ssb`; `Properties.Set` needs `ssv`. Explicit Boolean variants fix Powered, Pairable and Trusted calls. Forget now passes `dbus.ObjectPath`, producing `o` rather than `s`. Real dbus-python serialization tests reproduce the original wrong signature as a negative control and require all repaired call signatures.
- **Wi-Fi selection:** fixed privileged nmcli arguments use the existing development image's sudo authorization, with `--ask` and a private PTY. Passwords/PINs never enter arguments or diagnostics. Success requires a zero exit status; errors and cancellation release the child without returning secret-containing output. Authorization errors are not treated as Wi-Fi password prompts. This improves the failing path, but the Mac's actual connection failure still needs a physical retest.
- **Combined-band networks:** AP rows retain separate BSSID identities and now show reported 2.4/5/6 GHz, explaining duplicate SSIDs. A shared router SSID is supported. The terminal menu defaults conceptually to automatic band selection: 5 GHz-only is optional, explicitly labelled and confirmed. Saving a preference never requests a disconnect, clears stale AP locking for automatic selection, and can repair an inactive saved profile. Explicit reconnect uses `--ask` and reports failure honestly.
- **EGL synchronization:** swap-interval requests now check SDL success/failure, warn on driver rejection and expose `swap-vsync`, `swap-immediate`, `swap-failed` or Wayland `compositor` in the presentation line. A rejected V-sync request no longer enables the extra fence/glFinish wait. Successful synchronization retains its established path. The driver-reported interval is logged separately: zero can mean unavailable, so it is not presented as proof of physical tearing.
- **Overlay/render contention:** hardware/sysfs/filesystem sampling is moved outside the graph-history mutex. The renderer can copy the last graph snapshot without waiting on those potentially slow reads. Sensor sampling remains bounded/cached; the rounded theme and graphs are preserved. This removes a concrete blocking dependency; no FPS gain is claimed until a native build and Mac comparison.

The complete production patch remains rooted in the pinned Vibemis commit. Its updated checksum is recorded in SOURCES.lock and synchronized into the offline installer. Kernel/driver/library packages, surface/queue depth, hardware decode and native X11 remain unchanged. There is no forced real-time scheduling, power/governor change, permanent debug tracing, busy-wait pacing or enlarged latency-hiding queue.

## Reversible presets and comparisons

`eclipseos-streaming` is installed by future images and the one-time trusted updater bootstrap. It runs as the moonlight user, without sudo, and refuses saved-setting changes while Eclipse runs. It edits both `[General]` streaming keys and the `[eclipse]` local-overlay key using their actual QSettings sections. It owns only explicitly changed streaming keys, preserves all other Qt settings/hosts/theme/backgrounds, journals interrupted writes, and refuses to overwrite settings subsequently edited in Eclipse.

| Mode | Purpose |
| --- | --- |
| `balanced` | 1080p60, HEVC hardware decoding, 20 Mbps, SDR 4:2:0, V-sync on, VRR/frame-pacing worker off, stream-statistics and local hardware overlays off for a comparison baseline |
| `latency` | Same baseline, V-sync off; lower synchronization delay is the goal, tearing is the tradeoff |
| `opengl-test` | Change only preferred renderer to OpenGL/EGL; retain decoder and other settings |
| `vulkan-test` | Change only preferred renderer to Vulkan; retain fallback behavior if initialization fails |
| `auto-renderer` | Restore automatic renderer preference; does not restore every preset key |
| `restore` | Restore the original owned keys, leaving unrelated later edits intact |
| `status` | Show only tuning keys and snapshot availability, not hosts/tokens |
| `diagnose` | Bounded read-only capture of display/driver/radio and CPU/GPU/power context |

These are **testable presets**, not a promise of better FPS. The renderer preference is an attempt; use the actual Renderer line/log after a later native build to confirm what initialized. Compare the same game/host scene at 60 FPS for at least a minute per mode, changing one variable at a time. Compare with overlays off, then re-enable the selected compact/detailed graphs to measure their effect. Keep host frame-generation, encoder settings and refresh-rate changes separate from client comparisons.

From tty2:

```sh
eclipseos-streaming menu
eclipseos-streaming status
# Close Eclipse before these saved-setting changes:
eclipseos-streaming balanced
eclipseos-streaming opengl-test
# Run during a stream; no rescan or networking/service changes:
eclipseos-streaming diagnose --seconds 30
# Close Eclipse, then return to your original settings:
eclipseos-streaming restore
```

The settings menu offers **s) Streaming tuning / renderer diagnostics** on a future image. The current flashed image has neither that entry nor these fixes until explicitly installed through a trusted checkout/update; this work did not alter the user's USB.

## Software investigation and acceptance still required

1. Confirm the physical GUI can connect to the combined-band router and Bluetooth can power/scan/trust/forget with the repaired helpers. Keep tty2 recovery available.
2. Run the native frontend/Qt/decoder/overlay checks on this exact source before a real frontend package/image. Three new formatter tests, the EGL synchronization change and the overlay mutex change are **not natively compiled or runtime-verified** during this no-build preparation.
3. Compare actual presentation frontend, V-sync on/off, overlay off/on and matched client/display rates. Capture incoming, decoded, rendered and drop counts over sustained intervals; a single screenshot cannot identify the scheduler/driver that caused the queue overflow. Do not raise queue depth just to lower the displayed drop percentage.
4. If EGL import/presentation fails, inspect its initialization error and capabilities before changing Intel/Mesa/libva packages. Such driver/library changes require a separately validated base release under the current update policy.

An optional diagnostic report is saved privately to `~/.local/state/eclipseos/streaming/diagnostics.json`. It includes display modes, filtered OpenGL/VA-API identity, active AP radio measurements without SSID/BSSID, per-core CPU load/frequency, GPU frequency, memory-pressure counters, power source and thermal counter trends. It does not probe paired devices, export network credentials/host tokens or modify services. Missing readings remain Unavailable; a quiet sample does not certify hardware health. The current priority is software/rendering.

## Source validation

- **93 Python tests pass:** 35 updater, 7 controls, 17 control-center, 6 BlueZ lifecycle, 4 real D-Bus serialization, 5 terminal Wi-Fi, 5 real Wi-Fi PTY and 14 preset/diagnostic tests.
- Static validation, exact-source gate fixtures, runtime GPU/media-key fixtures, embedded payload equality, patch application against clean pinned source and `git diff --check` pass.
- The new manual source-only workflow requires the real D-Bus and PTY tests, rather than silently skipping missing dependencies.
- No new native frontend, OS image or deployable signed package has been built, and no Mac installation/performance improvement is claimed.

Primary references for the repaired protocol paths: [dbus-python typed variants](https://dbus.freedesktop.org/doc/dbus-python/tutorial.html), [NetworkManager nmcli authentication/activation](https://networkmanager.dev/docs/api/latest/nmcli.html). [SDL swap-interval request](https://wiki.libsdl.org/SDL2/SDL_GL_SetSwapInterval) and [reported interval limitations](https://wiki.libsdl.org/SDL2/SDL_GL_GetSwapInterval). Renderer/pacing conclusions come from the pinned repository source and the supplied screenshot.
