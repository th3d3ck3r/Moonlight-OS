# Codex build/fix prompt

Work directly in `th3d3ck3r/Moonlight-OS`. This is a real reproducible appliance image project, not a throwaway script.

Target hardware: **MacBookPro14,1 — 2017 13-inch non-Touch-Bar MacBook Pro**.
Target server: **Vibepollo / Sunshine-compatible host**.
Goal: a compact x86_64 UEFI USB image that boots Fedora 44 directly into CocoOS, with pinned upstream Moonlight as an automatic fallback/reference client.

Before changing anything, inspect the entire repository and `SOURCES.lock`. Do not update pinned upstream revisions unless needed to fix a demonstrated build/runtime failure; document any pin change.

Required invariants:
- Keep the v0.1 raw image below 14,000 MiB so it fits a normal 16 GB USB drive. Do not strip build/debug tooling from v0.1.
- Do not install GNOME/KDE or a compositor.
- Use native X11 for v1.
- Preserve i915 and Intel VA-API H.264/HEVC decode.
- Preserve BCM4350 `brcmfmac`, Wi-Fi power-save off, and `roamoff=1` latency tuning.
- Preserve Bluetooth/controller support.
- Preserve AirPods Pro 2 playback-only A2DP policy: no HSP/HFP microphone/headset roles, latency/quality switch, SBC/SBC-XQ/AAC.
- Preserve DualSense USB/Bluetooth support while suppressing its USB speaker/microphone/headset audio card only.
- Preserve the pinned MacBook Cirrus audio driver.
- Do not bundle FaceTime camera firmware.
- Do not touch the Mac internal disk from first boot.
- Wi-Fi, Bluetooth, Moonlight pairing, and settings must persist on the USB.
- Vibepollo must work via standard Sunshine/GameStream behavior; do not require CocoOS Companion/Apollo-only APIs.
- Keep upstream Moonlight installed as a fallback.
- Keep SSH disabled by default.

Tasks:
1. Run `./scripts/validate.sh` and fix static problems.
2. Audit Fedora 44 package names against current repositories and RPM Fusion.
3. Audit the Kickstart for UEFI partitioning, XFS root growth, user/autologin, Xorg startup, and first-boot networking.
4. Audit CocoOS and Moonlight build dependencies at the pinned commits, including current QtMultimedia/QML runtime needs.
5. Audit the `snd_hda_macbookpro` DKMS build against the installed target kernel rather than the installer kernel.
6. Build the image with `./scripts/build-image.sh` in a Fedora 44 environment. Fix every build error cleanly in the repo.
7. Validate the resulting GPT image with `scripts/inspect-image.sh`: EFI System Partition exists, root partition exists, image is <14000 MiB, `EFI/BOOT/BOOTX64.EFI` exists, and the root filesystem contains both client binaries and diagnostics.
8. Boot-test the raw image with `scripts/test-ovmf.sh`. It must use a copy-on-write overlay and observe `MOONLIGHT_OS_BOOT_OK` over serial after the multi-user boot path. Hardware-specific Mac tests require the real MacBook.
9. Update `BUILD_STATUS.md` with exactly what passed, what remains hardware-only, and any known issues.

Do not claim MacBook hardware success from QEMU. Do not hide failures. Prefer a bootable conservative image over extra features.
