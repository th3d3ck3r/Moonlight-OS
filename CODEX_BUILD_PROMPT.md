# Moonlight-OS — Codex completion prompt

## Repository — work here, not in a throwaway project

This project already has my GitHub repository:

`https://github.com/th3d3ck3r/Moonlight-OS`

Work **directly in this existing repository**. Inspect the current `main` branch before editing. Preserve all existing work, history, CI, diagnostics, documentation, and source pins. Do not create a replacement repository, detached rewrite, or throwaway copy. Commit all useful fixes back to this repository.

You have permission to spend my available ~5-hour Codex usage on this task. Use it **extremely efficiently**. The objective is a **completed, reproducible, bootable v0.1 image**, not a long explanation.

## Target

Hardware: **MacBookPro14,1 — 2017 13-inch non-Touch-Bar MacBook Pro, Intel i5 / Iris Plus 640**.

Server target: **Vibepollo / Sunshine-compatible host**.

OS goal: Fedora 44 x86_64 appliance/live USB with a remembered boot selector for **Vibemis, Artemis, Pegasus, vanilla Moonlight and CocoOS**. Initial default and launch-failure fallback are vanilla Moonlight. Pegasus launches the four streaming clients; it is not itself a streaming decoder.

v0.1 is intentionally a larger development/debug image and may use a normal **16 GB-or-larger USB**. Runtime should remain comfortable on the MacBook's 8 GB RAM.

## Current checkpoint — do not rediscover solved work

Read `BUILD_STATUS.md`, `SOURCES.lock`, `docs/FRONTEND_BLUETOOTH_INTEGRATION.md`, the current GitHub Actions history, and the current scripts before changing anything. Keep each task prompt self-contained; do not combine the separate GUI, telemetry or minimization plans. Published download links, README and release-facing status must remain unchanged until the user validates this candidate on the physical Mac.

Already proven in previous CI work:

- Fedora 44 package transaction resolves with RPM Fusion.
- Fedora 44 SDL2 compatibility packages are used.
- CocoOS pinned source configures/builds.
- Upstream Moonlight pinned source configures/builds.
- Moonlight's Linux accelerated feature probes see X11, EGL, VA-API X11/DRM, FFmpeg, libplacebo, Opus, SDL2 and the intended Qt stack.
- Fedora's broken base-media `igt-gpu-tools 2.2` is bypassed; current IGT is installed from updates and `intel_gpu_top` retained.
- Explicit X11/libinput, GPU diagnostic, root-growth, kmod and hardware-payload checks have already been added.
- Automatic image-build spam was disabled; use the controlled one-shot build path.
- Recent audits added/fixed the Cirrus DKMS GCC16 path. **Verify the current repo state rather than reverting to older audio attempts.**
- All six source audits passed in run **36994719874**. All six audits also passed for build commit **32bc89855f8bac3caf90b9d5177ae583bc50313d**, in run **36995905423**. Re-run checks appropriate to any subsequent code changes.

Candidate build **36995905431** completed successfully from commit **32bc89855f8bac3caf90b9d5177ae583bc50313d**. Installed-image inspection and strict OVMF UEFI validation passed. Artifact **11223945065** contains the compressed raw image and checksum. Physical testing of this candidate is pending. Reuse this candidate when available; do not trigger another full build without an authorized source change, missing artifact or explicit user request. The historical Cirrus build blocker is resolved; inspect current evidence before changing that path.

## Required invariants — do not regress these

- Native **X11** for v1; no GNOME, KDE, Gamescope, compositor, or full desktop.
- Intel `i915` DRM and **hardware VA-API H.264/HEVC** decode.
- Explicitly reject llvmpipe/softpipe software rendering in runtime diagnostics.
- Iris Plus 640/Mesa OpenGL path and GPU/video-engine telemetry.
- Apple SPI keyboard and trackpad through libinput.
- Generic USB/Bluetooth keyboard and mouse support.
- BCM4350 `brcmfmac`; Wi-Fi power saving off; `roamoff=1` latency baseline.
- NetworkManager Wi-Fi UI/helper; settings persist.
- Bluetooth UI/helper; settings persist.
- **PS5 DualSense** USB + Bluetooth through `hid-playstation`.
- Disable only the DualSense speaker/microphone/headset audio endpoints; keep controller HID functionality.
- **AirPods Pro 2** playback-only A2DP. No HSP/HFP microphone/headset switching.
- AirPods Low-Latency ↔ Quality preference switch.
- SBC/SBC-XQ/AAC support when supplied by Fedora/PipeWire; verify codec plugins rather than assuming.
- PipeWire/WirePlumber audio stack.
- MacBook Cirrus internal-audio driver if it can be made reliable on the selected Fedora kernel.
- Red text on black diagnostic console.
- Easy settings menu from tty2.
- Preserve the remembered five-way boot selector; vanilla Moonlight is the initial default and fallback. Preserve CocoOS restart handling and English labels.
- Preserve full Intel nonfree iHD hardware decode, native Retina/Openbox fullscreen handling, stream-only mouse shortcut, 100-row console, speaker restore and Mac volume/display/keyboard-backlight shortcuts.
- Build pinned Vibemis and Artemis natively; do not restore the crashing Vibemis AppImage. Keep Pegasus checksum-pinned with four explicit collection members.
- Generic Bluetooth pairing must retain one live confirmation-capable agent and verify paired/trusted/connected states. Forgetting requires explicit confirmation; do not silently erase bonds or restrict device names by brand.
- Vibepollo must work through standard Sunshine/GameStream behavior. Do not require CocoOS Companion/Apollo-only APIs.
- SSH disabled by default.
- Do not bundle FaceTime camera firmware.
- Do not touch the internal Mac SSD during the live-USB phase.
- First-boot/root-growth code must preserve the bootable USB and expand safely.
- Keep v0.1 raw image below **14,000 MiB** so it fits a normal 16 GB USB.
- Keep development/debug tooling needed to diagnose the physical Mac.

## Efficiency rules — important

Use the remaining usage like an engineer diagnosing CI, not by repeatedly rebuilding everything.

1. **Read the exact failing log before editing.**
2. Reproduce a failure with the **smallest possible audit** first.
   - package issue → Fedora package audit
   - Cirrus issue → isolated audio/DKMS audit
   - shell/Kickstart issue → static validation / `ksvalidator`
   - UEFI issue → image inspection / OVMF test
3. Never launch a full image build to test something that a smaller audit can prove.
4. Make the minimum clean fix for the demonstrated failure.
5. Re-run the targeted audit.
6. Run the full repository audit.
7. Only after all audits pass, trigger **one** full image build.
8. If that build fails, collect the preserved logs, identify the exact next blocker, and repeat.
9. Do not make speculative refactors while debugging.
10. Do not spend tokens repeatedly explaining already-proven architecture.
11. Keep user-visible progress terse: current failure → fix → test result.
12. Do not delete diagnostics just to make CI green.
13. Do not weaken a required hardware check merely because QEMU cannot satisfy Mac-specific hardware.
14. Do not silently drop requested hardware support to obtain a green image.

## Quadruple-check pass before the final full build

Perform four explicit passes:

**Pass 1 — structure**
- shell syntax
- Kickstart structure and `ksvalidator`
- heredocs
- systemd units
- workflow triggers
- source pins
- no stale/duplicated blocks

**Pass 2 — Fedora/package/build**
- every Fedora/RPM Fusion package resolves
- correct Fedora 44 package names
- pinned CocoOS configure/build prerequisites
- pinned Moonlight configure/build prerequisites
- X11/EGL/VA-API/libplacebo/FFmpeg/SDL/Qt feature probes
- exact target kernel + kernel-devel consistency
- Cirrus build prerequisites including tools downloaded/called by the driver

**Pass 3 — installed image payload**
- GPT/EFI/boot/root partitions
- `EFI/BOOT/BOOTX64.EFI`
- kernel/initramfs
- all five frontend executables, selector/launcher/Bluetooth helpers and pinned installation receipts
- i915/VA-API userspace
- libinput/input tools
- brcmfmac/network tools
- Bluetooth/PipeWire/WirePlumber policies
- AirPods helpers
- DualSense helpers and audio suppression
- Cirrus module if internal audio is enabled
- root-growth service
- settings/recovery console
- required debug tools

**Pass 4 — boot validation**
- inspect raw image read-only
- QEMU/OVMF boot from a qcow2 overlay, never modifying the release raw image
- require `MOONLIGHT_OS_BOOT_OK`
- confirm expected systemd/multi-user appliance path
- only then compress/upload artifact and checksum

OVMF proves generic x86_64 UEFI only. Do **not** claim MacBook hardware success until tested on the real Mac.

## Cirrus audio rule

Internal audio is important, but diagnose it in isolation before another full build.

Use the repo's current audio-audit path against the same Fedora kernel the image will install. Check:
- matching `kernel-devel`
- `wget`/download prerequisites used by the driver preparation script
- DKMS source directory/version
- actual compiler flags that reach the nested kernel-module build
- GCC16 compatibility flags
- output module path
- `depmod`
- final `snd-hda-codec-cs8409.ko*` presence

Do not revert blindly to an older `dkms.conf`. Compare the current repo, upstream driver Makefile, current Fedora guide/known-good recipe, and the actual compiler log.

If the driver is genuinely incompatible with the chosen current kernel after a focused attempt, document the exact compiler/API blocker and evaluate a **known-compatible Fedora 44 kernel pin** rather than removing internal audio outright. Do not change kernels unless the full GPU/input/network stack remains supported and the decision is documented.

## Build sequence

1. Inspect current repository/head and Actions history.
2. Run/fix `./scripts/validate.sh`.
3. Run/fix the Fedora package + pinned-source configure audit and `scripts/audit-frontends.sh` in the same Fedora container. Run Bluetooth/selector PTY fixtures. Software-rendered X11 startup is a CI smoke test only; keep runtime hardware diagnostics strict.
4. Run/fix the isolated Cirrus audio audit.
5. Quadruple-check the repository as described above.
6. Trigger one full image build.
7. On failure, inspect the uploaded installer/build diagnostics and fix the exact blocker.
8. Repeat targeted audit → full audit → single image build until the image completes.
9. Run raw-image inspection.
10. Run the OVMF boot gate.
11. Confirm compressed `.raw.xz` + SHA-256 artifact exists.
12. Record candidate build/audit evidence in the internal integration document and report the artifact to the user. Hold published download links, `BUILD_STATUS.md` and `README.md` promotion until the user confirms physical boot. Distinguish OVMF and fixture results from real Bluetooth, AirPods and streaming tests.

## Definition of done

Do not call this finished merely because static CI is green.

A successful v0.1 requires:
- all static/Fedora/source/audio audits green;
- Fedora disk image build completes;
- image inspection passes;
- OVMF UEFI boot passes and emits `MOONLIGHT_OS_BOOT_OK`;
- compressed raw image and checksum are produced as artifacts;
- documentation accurately states what is proven in CI and what still requires the physical MacBook.

Then stop. Do not start cosmetic v2 work.

If a truly external blocker prevents a completed build, leave the repo in a clean reproducible state and document the exact blocker, exact failing command/log, what was tried, and the smallest next action. Otherwise continue fixing until the completed build exists.
