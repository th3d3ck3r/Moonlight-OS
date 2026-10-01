# 🌙 Moonlight-OS

A tiny, controller-friendly Fedora appliance for turning a **2017 13-inch non-Touch-Bar MacBook Pro (MacBookPro14,1)** into a dedicated Moonlight client for a **Vibepollo / Sunshine-compatible host**.

The normal boot path is deliberately short:

```text
Apple EFI → Fedora 44 → NetworkManager → Xorg → CocoOS → Vibepollo/Sunshine
                                           ↘ upstream Moonlight fallback
```

## Design targets

- Boot from an 8 GB-or-larger USB drive without touching the internal SSD.
- Native x86_64 UEFI boot for the MacBookPro14,1.
- Intel Iris Plus 640 via the kernel `i915` driver.
- VA-API hardware decode for H.264/HEVC.
- Broadcom BCM4350 Wi-Fi and Bluetooth using the in-kernel drivers/firmware path.
- Wi-Fi power saving disabled to reduce latency spikes.
- USB/Bluetooth controller support.
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

The GitHub Actions workflow builds a UEFI partitioned disk image using Fedora's `livemedia-creator` and OVMF. The image is approximately 6.5 GiB before compression and is intended to fit on an 8 GB USB drive.

Locally, build from a Fedora 44 x86_64 host with virtualization available:

```bash
sudo dnf install -y lorax-lmc-virt qemu-kvm edk2-ovmf wget xz
sudo ./scripts/build-image.sh
```

Output:

```text
out/moonlight-os-mbp14-1.raw.xz
out/moonlight-os-mbp14-1.raw.xz.sha256
```

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

If no saved network is available, the appliance opens `nmtui-connect` on tty1 before launching the graphical client. After the connection is saved, subsequent boots launch straight into CocoOS.

If Bluetooth is missing immediately after switching from macOS, the BCM4350C0 may still have macOS' UART baud rate retained. Shut down and perform the standard SMC reset once, then boot Moonlight-OS again.

Useful consoles:

- `Ctrl+Alt+F1` — appliance session
- `Ctrl+Alt+F2` — diagnostic login console

The local user is `moonlight`. It has passwordless sudo in this diagnostic v1 image. Do not expose SSH to untrusted networks; SSH is disabled by default.

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
