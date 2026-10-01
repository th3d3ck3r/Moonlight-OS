# 🌙 Moonlight-OS

A controller-friendly Fedora development appliance for turning a **2017 13-inch non-Touch-Bar MacBook Pro (MacBookPro14,1)** into a dedicated Moonlight client for a **Vibepollo / Sunshine-compatible host**.

The normal boot path is deliberately short:

```text
Apple EFI → Fedora 44 → NetworkManager → Xorg → CocoOS → Vibepollo/Sunshine
                                           ↘ upstream Moonlight fallback
```

## Design targets

- Boot from a **16 GB-or-larger USB drive** without touching the internal SSD. v0.1 intentionally keeps build/debug tooling; the later appliance release will be smaller.
- Native x86_64 UEFI boot for the MacBookPro14,1.
- Intel Iris Plus 640 via the kernel `i915` driver.
- VA-API hardware decode for H.264/HEVC.
- Broadcom BCM4350 Wi-Fi and Bluetooth using the in-kernel drivers/firmware path.
- Wi-Fi power saving disabled to reduce latency spikes.
- **PS5 DualSense support over USB and Bluetooth** via `hid-playstation`, BlueZ, Fedora's SDL2 compatibility layer, joystick udev rules, and controller diagnostics.
- Internal audio through the MacBook-specific Cirrus CS8409/CS42L83 driver.
- X11 with no desktop environment and no compositor.
- CocoOS as the console UI, with pinned upstream Moonlight as a recovery/reference client.
- Persistent Wi-Fi, Bluetooth, pairing, and Moonlight/CocoOS settings.
- Target idle memory below 2 GB; 8 GB RAM is comfortably sufficient.

## Why two Moonlight clients?

CocoOS is a Moonlight-Qt fork with a controller-first console interface. Its current UI is still moving quickly, so Moonlight-OS also installs a pinned upstream Moonlight build. If CocoOS exits repeatedly, the launcher falls back to upstream Moonlight automatically.

The default client can be changed from a console with:

```bash
sudo moonlight-os-client cocoos
sudo moonlight-os-client moonlight
```

## Building the image

The GitHub Actions workflow builds a UEFI-partitioned development disk image using Fedora's `livemedia-creator` and OVMF. v0.1 is allowed to grow to **under 14,000 MiB raw** so it fits a normal 16 GB USB while retaining Git, GCC, DKMS, kernel headers, source trees, and diagnostic tooling.

Locally, build from a Fedora 44 x86_64 host with virtualization available:

```bash
sudo dnf install -y lorax-lmc-virt qemu-kvm qemu-img edk2-ovmf curl xz util-linux xfsprogs e2fsprogs dosfstools pykickstart
sudo ./scripts/build-image.sh
```

Output:

```text
out/moonlight-os-mbp14-1.raw.xz
out/moonlight-os-mbp14-1.raw.xz.sha256
```

## Automated UEFI preflight

A build is not considered flashable merely because Fedora produced a raw disk. Before compression/upload, Moonlight-OS:

1. inspects the GPT partitions and mounts them read-only;
2. requires the removable-media path `EFI/BOOT/BOOTX64.EFI` plus Fedora EFI files;
3. verifies CocoOS, upstream Moonlight, settings/diagnostic helpers, and Bluetooth policies are present;
4. boots a copy-on-write overlay of the raw image under QEMU/OVMF;
5. requires the guest to reach multi-user boot and emit `MOONLIGHT_OS_BOOT_OK` over the serial console.

The OVMF test does not modify the release raw image and does not prove Mac-specific hardware. It proves the generic x86_64 UEFI boot path before the image is flashed to the MacBook.

## Flashing

**This erases the destination USB. Double-check the device name.**

Linux:

```bash
xzcat moonlight-os-mbp14-1.raw.xz | sudo dd of=/dev/sdX bs=16M status=progress conv=fsync
```

macOS:

```bash
diskutil list
diskutil unmountDisk /dev/diskN
xzcat moonlight-os-mbp14-1.raw.xz | sudo dd of=/dev/rdiskN bs=16m
diskutil eject /dev/diskN
```

On the MacBook, hold **Option (⌥)** at power-on and choose **EFI Boot**.

## First boot

If no saved network is available, the appliance opens the Moonlight-OS Wi-Fi helper on tty1; its Connect option uses `nmtui-connect`. After the connection is saved, subsequent boots launch straight into CocoOS.

If Bluetooth is missing immediately after switching from macOS, the BCM4350C0 may still have macOS' UART baud rate retained. Shut down and perform the standard SMC reset once, then boot Moonlight-OS again.

Useful consoles:

- `Ctrl+Alt+F1` — appliance session
- `Ctrl+Alt+F2` — diagnostic login console (black background / red text)

The local user is `moonlight`. It has passwordless sudo in this diagnostic v1 image. Do not expose SSH to untrusted networks; SSH is disabled by default.

Normal use should not require a command line. If you intentionally enter a recovery/debug shell, Moonlight-OS defaults to a **black background with red text**.

DualSense audio behavior: the controller's **speaker, microphone, and headset audio endpoints are disabled** on USB. The controller remains fully available through `hid-playstation` for normal input and supported haptics/features. Bluetooth DualSense is HID-only on mainline Linux, so no controller audio device is exposed there.

DualSense helpers:

```bash
dualsense-check
dualsense-pair
```

For Bluetooth pairing, hold **CREATE + PS** until the light bar flashes rapidly, then use the pairing helper.

## AirPods Pro 2

AirPods Pro 2 are treated as **playback-only A2DP devices**. HSP/HFP headset/microphone roles are disabled. WirePlumber is configured with the documented `bluetooth.profile-preference = "latency"` setting and A2DP codecs `sbc`, `sbc_xq`, and `aac`. The settings menu can switch between **Low Latency** and **Quality** preference without enabling microphone mode.

## Network and Bluetooth menu

Normal streaming should not require a shell. Press `Ctrl+Alt+F2` for the red-on-black recovery/settings console; it automatically opens `moonlight-settings`, which provides Wi-Fi, Bluetooth, AirPods Pro 2, DualSense, diagnostics, and client selection. On a first boot with no saved network, the appliance invokes the Wi-Fi helper automatically before starting X11.

## Fedora 44 installer note

Fedora 44 base installer media contains an older `igt-gpu-tools 2.2` build with a stale libproc2 dependency. Moonlight-OS installs the current IGT package from Fedora updates during post-install instead, preserving `intel_gpu_top` GPU/video telemetry without allowing that base-media packaging bug to block Anaconda.

## Hardware verification

Run:

```bash
sudo moonlight-os-verify
```

It checks the model identifier, i915, DRM render nodes, VA-API profiles, Wi-Fi, Bluetooth, audio, controller devices, X11 components, both clients, and memory use.

For streaming, start with **1080p60 + H.264 + hardware decoding + V-Sync/frame pacing enabled**. Then compare HEVC, Wi-Fi vs Ethernet, and CocoOS vs upstream Moonlight using Moonlight's performance overlay.

## Source locks

See [`SOURCES.lock`](SOURCES.lock). Build-critical upstream commits and the Fedora installer checksum are pinned so a future branch update cannot silently change the image.

## Important v1 limitations

- The FaceTime camera is intentionally omitted; it is irrelevant to streaming and requires another third-party driver/firmware path.
- Internal audio uses a third-party MacBook driver pinned in `SOURCES.lock`.
- The image does not auto-update the kernel. That is intentional: the prebuilt MacBook audio module is tied to the installed kernel. Build a new Moonlight-OS image when moving kernels.
- CocoOS' optional host Companion features are not required. Vibepollo is treated as a standard Sunshine/GameStream-compatible server, so ordinary Moonlight discovery, pairing, app listing, streaming, and input remain the baseline.

## License

Moonlight-OS build scripts are GPL-3.0. The image incorporates or builds third-party software under each upstream project's license, including Moonlight-Qt/CocoOS (GPL-3.0). See `docs/THIRD_PARTY.md`.
