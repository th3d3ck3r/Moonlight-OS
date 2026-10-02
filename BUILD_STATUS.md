# Build status

Status: **v0.1 image built; installed-payload inspection and OVMF boot passed**

Validated before the first CI image build:

- Target fixed to MacBookPro14,1 (2017 13-inch non-Touch-Bar).
- Fedora 44 Everything installer pinned by SHA-256.
- CocoOS, upstream Moonlight, and the MacBook Cirrus audio driver pinned by commit SHA.
- UEFI/GPT layout defined with EFI System Partition, separate /boot, and XFS root.
- i915/VA-API, BCM4350 Wi-Fi/Bluetooth, X11, controller, PipeWire, and diagnostic packages included.
- Wi-Fi power saving disabled and brcmfmac roaming disabled for latency testing.
- CocoOS has an automatic upstream Moonlight fallback.
- SSH disabled by default.
- Camera intentionally omitted.
- AirPods Pro 2 configured for playback-only A2DP with latency/quality preference switching; HSP/HFP disabled.
- DualSense speaker/microphone/headset audio endpoints suppressed without disabling controller HID.
- Red-on-black diagnostics/settings console added with Wi-Fi and Bluetooth helpers.
- v0.1 keeps Git/GCC/DKMS/kernel headers and source trees for hardware debugging; 16 GB USB target.
- Explicit X11 development headers and Mesa EGL/GL development headers are included so Moonlight's X11/EGL accelerated paths are compiled deliberately.
- Raw-image inspection requires the fallback Apple-friendly removable EFI path `EFI/BOOT/BOOTX64.EFI`.
- OVMF boot gate uses a copy-on-write overlay and requires a multi-user serial success marker before artifact compression/upload.
- Hardware verifier rejects llvmpipe/softpipe software OpenGL rendering.

## Completed CI validation — 2026-10-01

- Fresh [image build #40](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36919007483) succeeded at source commit `c8a97a3bc9f4f35c986c1233c28f08b6a6e77cc0`.
- [Audit #67](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36919007320) passed all five jobs: static, Fedora/package/pinned-source configuration, exact-kernel Cirrus compilation, image tools, and real GPT/XFS root growth.
- Installed kernel/module payload is checked against `6.19.10-300.fc44.x86_64` from `SOURCES.lock`.
- Read-only inspection passed GPT/EFI/boot/XFS layout, `EFI/BOOT/BOOTX64.EFI`, kernel/initramfs, both clients, enabled growth/marker services, settings/input/network/audio policies, required diagnostics, Intel VA-API userspace, and all required MacBook/controller modules.
- Both SBC and AAC codec plugins were verified in Fedora audit and the installed image. Headset/microphone roles remain excluded from the AirPods policy.
- QEMU/OVMF boot passed the strict serial `MOONLIGHT_OS_BOOT_OK` gate using a qcow2 overlay. The release raw image is not modified by validation.
- Raw size: **13,147,045,888 bytes (12.24 GiB)**, below **14,000 MiB**.
- [Validated artifact](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36919007483/artifacts/11193175513) contains the `.raw.xz` image and its SHA-256 file; both files were uploaded. Artifact retention ends October 15, 2026.

### Four verification passes

1. **Structure:** Bash helpers and embedded post-install syntax, Kickstart validation, systemd unit verification, workflow parsing/execution, matching source pins, and rejection of the old formatted partition-number query.
2. **Fedora/build:** complete package transaction, accelerated pinned-source feature probes, actual full client builds, exact-kernel DKMS compilation, and SBC/AAC plugin presence.
3. **Installed payload:** fresh disk inspection passed with direct filesystem probing, read-only loop devices, XFS `norecovery`, and ext4 `noload`.
4. **Boot:** generic UEFI/OVMF boot passed, root growth succeeded, and the required serial boot marker was observed before compression and upload.

### Fixes retained in the repository

- Container inspection creates missing loop-partition nodes from kernel metadata and uses `blkid` instead of udev-dependent `lsblk` filesystem columns.
- The inspector mounts `/boot` before checking its EFI mountpoint and never creates directories inside the read-only guest.
- Guest executable checks use inherited output descriptors instead of trying to create `/dev/null` in the read-only image.
- Root growth reads the partition number and parent disk from sysfs and validates them before writing. The exact former boot failure was `growpart: FAILED: partition-number must be a number`; the old `lsblk` result was unsuitable for its numeric argument.
- The focused growth audit expanded a disposable real GPT/XFS disk, preserved EFI and boot partition sizes, accepted `NOCHANGE`, and verified failure remains retryable without a completion marker.
- Failed validation retains a clearly labeled unvalidated image checkpoint and diagnostic logs. Recovery requires matching source/Kickstart checksums; an installed-payload change requires a fresh build. Manual workflow runs always build from scratch.
- OVMF failures can collect an additional direct-kernel diagnostic journal, which never substitutes for a successful OVMF gate.
- The checksum file names the downloaded image by basename, so Linux/macOS verification works outside the CI workspace.

### Remaining physical validation

Real i915/VA-API decode, OpenGL rendering, Apple SPI keyboard/trackpad, generic input, BCM4350 Wi-Fi/Bluetooth, internal Cirrus audio, AirPods Pro 2 latency/quality switching, DualSense HID/audio suppression, battery/thermal behavior, persistence, and Vibepollo/Sunshine streaming must be tested on the actual MacBook. OVMF proves generic x86_64 UEFI only. See `docs/TEST_PLAN.md` and the README flashing instructions.


## Fedora 44 installer workaround

The diagnostic Anaconda run exposed Fedora 44's known broken base-media `igt-gpu-tools 2.2-2.fc44`, which requires the obsolete `libproc2.so.0`. Moonlight-OS no longer asks Anaconda to solve that package from base media. The image installs `igt-gpu-tools` during `%post` with refreshed Fedora updates, where the audited package is `2.4-1.fc44`. This keeps `intel_gpu_top` without blocking installation.

The installer VM is allocated 4096 MiB RAM and 2 vCPUs for the Qt source builds. This is a build-time setting only; it does not change the 8 GB physical-RAM target.

## Physical Mac checkpoint — 2026-10-02

User booted the October 1 image on MacBookPro14,1 and streamed the Windows host desktop. Initial runtime defects were diagnosed on the actual device:

- i915 binds to **card1**, with **renderD128**; previous card0 checks were false failures.
- Fedora iHD 25.4.6 loaded but exposed no H.264/HEVC profiles. Installing RPM Fusion **intel-media-driver** loaded iHD 26.1.5 from `dri-nonfree`, exposing H.264 and HEVC/Main10 **VAEntrypointVLD** profiles. Actual hardware-decoder usage still needs an in-stream telemetry check.
- X11 already used native **2560×1600**. Reducing resolution was only a temporary workaround. Installing and starting **Openbox**, then restoring native resolution, fixed UI/stream sizing according to the user.
- **Control + Option + Shift + M** fixed stream-only desktop pointer speed. The UI pointer was already correct; game capture is preserved.
- Internal speakers became audible at the expected level after hardware mixer adjustment. Exact mixer values were not supplied; do not invent universal mixer defaults.
- **spi::kbd_backlight** exists, was off, and setting it to 50% worked.
- `stty rows 100` worked at native resolution and has a target-console login setting.
- CocoOS embedded console labels were French in the pinned source; an explicit English translation is now applied before compilation, with placeholders and source expectations checked.

The repair image is **built, inspected and OVMF-validated**. Current README links point to the repaired image. The fresh build ran from `eb907394d62f6245bfeae971155a3c7dc15e89e3` after audit #78 passed all five jobs. The exact build commit also passed all five jobs in audit #79. Source/kernel pins and both independent feature plans remain unchanged.

The media-key service reads only seven Linux brightness/volume event codes independently of X11 keyboard grabs. It ignores releases and repeated mute toggles, without grabbing input or changing game capture. Synthetic event checks and systemd unit checks pass. On October 2 the user confirmed **screen brightness, keyboard brightness and volume keys work on the Mac**. Mute and these keys during an active stream were not explicitly reported.

Saved-state behavior across reboot, AirPods modes, DualSense, sustained game performance, and actual decoder telemetry remain physical validation items. Exact hardware mixer values were not supplied, so new images include explicit mixer/save/restore helpers rather than invented default levels.

## Completed repair image — 2026-10-02

- [Build run 36972953272](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36972953272) succeeded at source `eb907394d62f6245bfeae971155a3c7dc15e89e3`.
- All five jobs passed on that exact source in [audit #79](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36972953285).
- Read-only installed-image inspection passed at 06:35 UTC, including the full nonfree iHD payload, Openbox/tools, mixer helper/restore, console setup and enabled local media-key service.
- Strict OVMF UEFI validation passed at 06:35:36 UTC; the unchanged boot gate requires `MOONLIGHT_OS_BOOT_OK` and uses a qcow2 overlay rather than modifying the release raw image.
- Raw size remains **13,147,045,888 bytes / 12.24 GiB**, below 14,000 MiB. [Artifact 11213197745](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36972953272/artifacts/11213197745) is **3,463,708,878 bytes** and contains the compressed raw image plus SHA-256 file. Retention ends October 16, 2026.
- Four passes covered structure/generated scripts/systemd units, full Fedora/source/audio audits and client compilation, installed payload, then the strict boot gate. Physical evidence is listed above; OVMF does not substitute for Mac hardware tests.

The separate terminal-interface prompt remains planning only. Crimson Apollo is now integrated in source for a later explicitly authorized image build; **the repaired download above does not contain the theme**. No additional image build has been started.

### Crimson Apollo source integration — 2026-10-02

The offline Kickstart payload installs the theme/plugin, selects it and regenerates the exact pinned kernel initramfs after DKMS. Serial diagnostics are retained; a bounded Plymouth quit precedes the tty1 network setup/X11 session. The future image inspector requires the theme and plugin in the initramfs. Native Plymouth 24.004.60 script/image/font/sprite execution passes at 320×200 through 2560×1600, including an offset viewport, two orbits, masked passwords, question/message ordering and a display-change callback. The local engine is the Ubuntu-packaged upstream version; the added audit job exercises the Fedora package independently. These checks are **not a daemon/KMS, OVMF or Mac boot validation**. Those require a later authorized build and physical test. See `docs/BOOT_ANIMATION.md`.
