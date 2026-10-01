# Shared compatibility and efficient build gates

Applies to [host overlay/dashboard](HOST_OVERLAY_PLAN.md) and [Crimson Glass GUI](LIQUID_GLASS_GUI_PLAN.md). Planning review completed October 1, 2026; implementation/runtime regression tests remain pending.

## Preserve the proven baseline

Use image build #40 (source `c8a97a3bc9f4f35c986c1233c28f08b6a6e77cc0`) as the image baseline, with successful five-job audit #67 and final documented-state audit #68. Keep the downloaded validated image/checksum for recovery. Current HEAD documentation does not change that image.

The original [CODEX_BUILD_PROMPT.md](../CODEX_BUILD_PROMPT.md) describes a historical pre-completion checkpoint. Consult [BUILD_STATUS.md](../BUILD_STATUS.md) for completed v0.1 status; use the original invariants, not its stale failure description. These follow-up plans are separately requested work and remain deferred until physical boot/basic streaming succeeds.

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
| Clients/protocol | CocoOS default/embedded build, upstream Moonlight reference/fallback, standard Sunshine/GameStream pairing/discovery/stream/input; Companion and stats APIs optional |
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

**2 — packages and client behavior.** Run the smallest changed-feature tests first: bounded API parser/auth/TLS/timeouts, lifecycle/thread ownership, overlay rendering/input, QML navigation/English/layout and settings failure paths. Validate new Fedora packages/imports/shader tooling, accelerated configuration and both patched client builds. Run all five repository audits (static, Fedora, audio, image-tools, root-growth) on the final candidate. Keep Cirrus/source checks even if feature code does not touch them.

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
- Final candidate: targeted tests → all five audits → one image build → inspection/OVMF → physical validation. Do not push unrelated edits while that build is running.
- On failure, read the exact saved log, change the smallest demonstrated cause and repeat the applicable checks. Recovery reuse requires matching hashes for every payload input; changed patches, resources or packages require a fresh installed image.
- Save a short checkpoint with candidate SHA, tests, remaining blocker and next command so work can resume without retracing it.

## Review outcome for these plans

The plans are compatible proposals after these corrections: existing stats bindings remain unchanged; privileged settings operations must preserve current network/audio policies; first-boot GUI must not gate the boot marker on network; theme and telemetry need independent failover; package footprint and full hardware checks remain mandatory.

No runtime feature implementation was tested during this document review. Only documentation is changed. All four passes must be executed with evidence once implementation exists.
