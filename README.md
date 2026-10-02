<div align="center">

# 🌙 Moonlight-OS
### Your MacBook. A dedicated streaming console. 🎮

**Fedora 44 · CocoOS + Moonlight · Intel x86_64 · Native UEFI**

A controller-friendly USB appliance for the **2017 13-inch non-Touch-Bar MacBook Pro — MacBookPro14,1**, connecting to **Vibepollo / Sunshine-compatible hosts**.

**[⬇️ Download](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36919007483/artifacts/11193175513) · [🚀 Setup](#quick-start) · [✨ Features](#features) · [🩺 Troubleshooting](#troubleshooting) · [🧪 Test plan](docs/TEST_PLAN.md)**

</div>

---

## ✅ v0.1 — built, inspected, boot validated

**Validated on October 1, 2026.** [Fresh build #40](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36919007483) installed Fedora, compiled both pinned clients and Cirrus audio, passed read-only image inspection, and booted through QEMU/OVMF with `MOONLIGHT_OS_BOOT_OK`. All five jobs in the [final repository audit #68](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36923967450) passed.

| 📦 Download details | Value |
| --- | --- |
| Artifact | [moonlight-os-mbp14-1](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36919007483/artifacts/11193175513) |
| ZIP contents | `moonlight-os-mbp14-1.raw.xz` + `moonlight-os-mbp14-1.raw.xz.sha256` |
| Download size | About **3.3 GiB** |
| Uncompressed image | **12.24 GiB / 13,147,045,888 bytes** |
| USB requirement | **16 GB or larger** |
| Artifact expires | **October 15, 2026** — run the build workflow for a fresh artifact |

> 🛠️ **October 2 physical testing found fixes missing from the downloadable October 1 image.** Installing the full Intel media driver exposed H.264/HEVC decode profiles; Openbox fixed client/stream sizing at native resolution; direct mouse control fixed desktop pointer speed; mixer adjustment fixed quiet speakers; keyboard backlight control worked. The repository includes these repairs and English CocoOS labels, but **a new image has not yet been built or OVMF-validated**. AirPods and DualSense remain untested on this Mac.

<a id="features"></a>

## ✨ What's inside

| Feature | Included configuration |
| --- | --- |
| 🎮 Console interface | **CocoOS** controller-first UI, with pinned upstream **Moonlight** as a fallback/reference client |
| ⚡ Intel acceleration | Kernel `i915`, Intel VA-API H.264/HEVC decode stack, Mesa, and GPU diagnostics for Iris Plus 640 |
| 🖥️ Lean graphics session | Native **X11**, with no desktop environment or compositor |
| 📶 Wi-Fi setup | NetworkManager, guided first-boot connection, saved networks, and Wi-Fi power saving disabled |
| ⌨️ Input support | Apple SPI keyboard/trackpad modules, libinput, and USB/Bluetooth mouse and keyboard tooling |
| 🕹️ DualSense | USB/Bluetooth input via `hid-playstation`, pairing helper, joystick rules, and diagnostics |
| 🔇 Controller audio policy | DualSense USB speaker, microphone, and headset endpoints disabled while retaining input |
| 🎧 AirPods Pro 2 | Playback-only **A2DP**, SBC/SBC-XQ/AAC codec configuration, and **Low Latency / Quality** preference selection |
| 🔊 Internal audio | Pinned third-party Cirrus CS8409/CS42L83 driver built for the installed kernel |
| 🛠️ Guided settings | Wi-Fi, Bluetooth, AirPods, controllers, diagnostics, and client selection from tty2 |
| 💾 Persistent setup | Wi-Fi, Bluetooth, pairing, and client settings saved on the USB; first-boot XFS root growth |
| 🌡️ Diagnostics | Hardware verifier, VA-API checks, `intel_gpu_top`, input tools, and thermal management |
| 🔒 Reproducible builds | Pinned upstream commits and Fedora installer checksum in [SOURCES.lock](SOURCES.lock) |

**Boot flow:** Apple EFI → Fedora 44 → NetworkManager → Xorg → CocoOS → your streaming host.

CocoOS is a Moonlight-Qt fork whose interface is still evolving. After repeated client failures, the launcher falls back to upstream Moonlight. You can also select either client manually.

**Performance targets:** idle memory below 2 GB and a low-latency streaming session. These are targets, not measured physical-hardware results. An 8 GB MacBook is the intended class of device.

<a id="quick-start"></a>

## 🚀 Quick start

### 1. Download and verify 🔍

[Download the validated GitHub Actions ZIP](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36919007483/artifacts/11193175513), then unzip it. GitHub may require you to sign in.

Run the checksum command in the directory containing both downloaded files:

```bash
# Linux
sha256sum -c moonlight-os-mbp14-1.raw.xz.sha256

# macOS
shasum -a 256 -c moonlight-os-mbp14-1.raw.xz.sha256
```

**Continue only if verification reports OK.**

### 2. Flash the USB 💾

> ⚠️ **Flashing erases the entire destination drive.** Replace the example device with your USB's actual device name. Verify its identity and capacity first; do not select the internal SSD.

**Linux** — inspect disks with `lsblk`, unmount the USB's mounted partitions, then:

```bash
xzcat moonlight-os-mbp14-1.raw.xz | sudo dd of=/dev/sdX bs=16M status=progress conv=fsync
```

**macOS** — these commands require `xzcat` to be installed:

```bash
diskutil list
diskutil unmountDisk /dev/diskN
xzcat moonlight-os-mbp14-1.raw.xz | sudo dd of=/dev/rdiskN bs=16m
diskutil eject /dev/diskN
```

### 3. Boot and connect 📶

1. Insert the USB into the target MacBook.
2. Hold **Option (⌥)** at power-on and select **EFI Boot**.
3. If no network is saved, use the Wi-Fi helper's **Connect** option, powered by `nmtui-connect`.
4. Once networking is configured, the appliance starts CocoOS. Add/discover your host and complete its pairing flow.
5. Start with **1080p60, H.264, hardware decoding, V-Sync, and frame pacing enabled**. Compare HEVC and network options after confirming a stable stream.

The appliance is designed to run from USB without installing to the internal SSD. Saved settings survive reboots.

## 🎛️ Everyday controls

| Shortcut / command | Purpose |
| --- | --- |
| **Ctrl+Alt+F1** | Return to the appliance session |
| **Ctrl+Alt+F2** | Open the black-and-red settings/recovery console |
| `moonlight-settings` | Launch the guided settings menu manually |
| `sudo moonlight-os-client cocoos` | Select CocoOS |
| `sudo moonlight-os-client moonlight` | Select upstream Moonlight |
| `sudo moonlight-os-verify` | Inspect hardware, graphics, networking, audio, input, clients, and memory |
| `dualsense-check` | Inspect controller support |
| `dualsense-pair` | Start guided Bluetooth controller pairing |

**DualSense pairing:** hold **CREATE + PS** until the light bar flashes rapidly, then use the pairing helper. The USB audio endpoints are suppressed; actual haptics and other controller features depend on the client and host.

**AirPods Pro 2:** pair through the settings menu and choose **Low Latency** or **Quality** preference. HSP/HFP microphone/headset roles are disabled. This preference does **not** guarantee a particular codec or latency; confirm negotiation and playback on your hardware.

**Local diagnostic user:** `moonlight`, with passwordless sudo in this development image. SSH is disabled by default. Normal boot and streaming should not require shell commands.

<a id="troubleshooting"></a>

## 🩺 Known limitations & troubleshooting

| Symptom / limitation | What to check or do |
| --- | --- |
| Bluetooth missing after switching from macOS | BCM4350C0 may retain macOS' UART baud rate. Shut down, perform the standard SMC reset for this MacBook once, and retry. |
| Wi-Fi missing or unstable | Open tty2 settings and run `sudo moonlight-os-verify`. BCM4350 firmware/driver behavior still needs physical validation; compare a supported Ethernet adapter if available. |
| Black screen, slow decode, or stutter | Compare upstream Moonlight with CocoOS. Start at 1080p60/H.264; inspect VA-API and the performance overlay. Run the verifier and observe video-engine activity with `intel_gpu_top`. |
| CocoOS exits repeatedly | The launcher provides upstream Moonlight fallback. Select it explicitly from settings if needed. |
| Internal speakers unavailable | Check the Cirrus module and PipeWire sink with the verifier. The driver is third-party and tied to the pinned kernel. |
| AirPods delay or unexpected codec | Check the active A2DP configuration and compare the two preferences. Actual latency depends on Bluetooth conditions and negotiated codec. Microphone mode is intentionally unavailable. |
| DualSense speaker/mic absent | Expected policy on USB. Controller audio is disabled; verify controller input separately. |
| Keyboard, trackpad, or controller misbehaves | Use the verifier and [input test checklist](docs/TEST_PLAN.md). Installed modules alone do not prove real-device operation. |
| Root expansion fails | First-boot growth must succeed or explicitly report NOCHANGE; other failures remain retryable. Inspect `journalctl -u moonlight-os-grow-root.service` from tty2. |
| Image download expired | Run **Build Moonlight-OS image → Run workflow → main** to produce a fresh validated artifact. |
| FaceTime camera unavailable | Intentionally omitted; its separate driver/firmware path is outside this streaming appliance. |
| Optional CocoOS Companion features | Not required or claimed. Standard Sunshine/GameStream-compatible discovery, pairing, app listing, streaming, and input are the baseline. |

**Fixed during this build:** container partition probing, read-only inspection mount order, Fedora OVMF firmware discovery, and first-boot root partition-number detection. Root growth now has real GPT/XFS expansion, NOCHANGE, and failure/retry audit coverage.

**Kernel updates:** this image does not auto-update the kernel. Build a new image when changing kernels so the MacBook audio module stays aligned.

## 🧪 Automated UEFI preflight — four validation passes

1. **Repository checks:** shell/Kickstart validation, embedded helpers, source pins, and configuration checks.
2. **Fedora checks:** package dependencies, accelerated client configuration, exact-kernel Cirrus compilation, and SBC/AAC plugins.
3. **Installed-image inspection:** GPT/EFI/boot/XFS layout, removable-media bootloader, both clients, settings helpers, policies, and hardware modules.
4. **Boot check:** QEMU/OVMF boots a copy-on-write overlay and requires `MOONLIGHT_OS_BOOT_OK` before compression and upload.

The overlay preserves the release raw image. The root-growth audit also checks actual partition/filesystem expansion, unchanged EFI/boot partitions, NOCHANGE handling, and retry after failure.

**Next: real hardware.** Follow [docs/TEST_PLAN.md](docs/TEST_PLAN.md) for GPU decode, Apple input, networking, audio, AirPods, controller behavior, and sustained streams. Compare CocoOS/upstream Moonlight and Wi-Fi/Ethernet using the performance overlay.

## 🏗️ Build your own image

### GitHub Actions

Open **Actions → Build Moonlight-OS image → Run workflow**, select `main`, and run it. Manual builds install from scratch and do not depend on temporary recovery artifacts. A successful run uploads the compressed image and checksum.

### Fedora 44 x86_64 host

Use a Fedora 44 host with virtualization available:

```bash
sudo dnf install -y lorax-lmc-virt qemu-kvm qemu-img edk2-ovmf curl xz util-linux xfsprogs e2fsprogs dosfstools pykickstart
sudo ./scripts/build-image.sh
```

Outputs:

```text
out/moonlight-os-mbp14-1.raw.xz
out/moonlight-os-mbp14-1.raw.xz.sha256
```

The development image stays **under 14,000 MiB raw** while retaining Git, GCC, DKMS, kernel headers, source trees, and diagnostic tools. A smaller appliance image is a future goal.

**Fedora installer workaround:** Fedora 44 base media includes an older `igt-gpu-tools 2.2` build with a stale libproc2 dependency. Moonlight-OS installs current IGT from Fedora updates during post-install, preserving GPU telemetry without blocking Anaconda.

## 📚 Project notes

- [Build status](BUILD_STATUS.md)
- [Hardware and streaming test plan](docs/TEST_PLAN.md)
- [Planned host stats overlay and dashboard button](docs/HOST_OVERLAY_PLAN.md) — follow-up after physical boot validation
- [Liquid Glass–inspired GUI plan](docs/LIQUID_GLASS_GUI_PLAN.md) — cohesive client and appliance settings redesign
- [Pinned sources](SOURCES.lock)
- [Third-party software](docs/THIRD_PARTY.md)

## ⚖️ License

Moonlight-OS build scripts are **GPL-3.0**. Included third-party software retains its upstream license, including Moonlight-Qt/CocoOS (GPL-3.0). See [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md).

---

<div align="center">

**🌙 Boot. Pair. Play.**  
Built for a dedicated streaming setup — with the diagnostics to keep improving it.

</div>

## ⌨️ Mac keyboard shortcuts and confirmed repairs

**Option = Alt; Control = Ctrl.** Use Fn for F-keys when your keyboard sends media keys instead. Command is not a substitute for Control. These shortcuts apply to the Linux USB appliance.

| Action | Mac keyboard |
| --- | --- |
| Return to CocoOS/Moonlight | Control + Option + F1 (add Fn if needed) |
| Open settings/diagnostic console | Control + Option + F2 (add Fn if needed) |
| Toggle direct desktop pointer / captured game mouse during a stream | **Control + Option + Shift + M** |
| Stop a console command | Control + C |
| Finish saving text entered with `tee` | Enter, then Control + D |
| Choose the internal sound card in `alsamixer` | F6 (add Fn if needed) |
| Mixer level / mute / exit | Arrow keys / M / Esc |
| Screen brightness | Brightness keys (F1/F2 media functions) |
| Keyboard lighting | Keyboard-light keys (F5/F6 media functions) |
| Mute / quieter / louder | Audio keys (F10/F11/F12 media functions) |

Openbox binds the brightness, keyboard-light and volume **media key symbols**. These new bindings still require physical testing; a streaming client may capture keys before Openbox receives them. Console switching and the stream mouse toggle were tested. Brightness and volume commands remain available from tty2.

### 🛠️ Repairs for the original downloadable image

- **Codecs:** `sudo dnf install intel-media-driver`, then `sudo vainfo --display drm --device /dev/dri/renderD128`. Require H.264 and HEVC **VLD** entries; installing a module alone is insufficient.
- **Sizing:** install Openbox with `sudo dnf install openbox`; start it with `DISPLAY=:0 openbox &`. Keep native **2560×1600**. A mode change from tty2 may fail while X11 is inactive; schedule it with `sleep 10; DISPLAY=:0 xrandr --output eDP-1 --mode 2560x1600`, then return to tty1 during the delay. New images start Openbox before either client and do not force a reduced display resolution.
- **Desktop pointer:** use the mouse-mode shortcut above. Keep captured mode available for games; local UI pointer speed needs no change.
- **Quiet speakers:** select the internal sound card in `alsamixer`, adjust available Master/Speaker/PCM controls, then run `sudo alsactl store`. New images offer `moonlight-audio` and settings option 9 to open the mixer and save on exit, and restore existing saved mixer state at boot. No untested maximum mixer level is forced.
- **Keyboard lighting:** `sudo brightnessctl -d spi::kbd_backlight set 50%`. New images initialize this LED at 50%; systemd can subsequently restore saved brightness.
- **Console:** `stty rows 100` was confirmed at native panel resolution. New images apply it on tty1/tty2 login for this target. It is a console geometry setting, not a graphical scale setting.
- **English:** the pinned CocoOS console has French source labels. The build applies a checked English source translation before compilation. OS locale changes alone do not translate the original binary. Host-provided app names and artwork remain host data.

The full Intel driver replaces Fedora's codec-restricted driver in the package manifest and read-only image check. GPU diagnostics now locate i915 and its corresponding render node dynamically rather than assuming `card0`, and require successful VA-API initialization plus decode entrypoints. AirPods testing is still pending.

### 🔆 Test brightness and volume keys on the existing USB

Run these from the diagnostic shell (a new repository folder is required only once):

```bash
git clone https://github.com/th3d3ck3r/Moonlight-OS
bash Moonlight-OS/scripts/install-media-keys.sh
```

The helper installs the same Openbox bindings as new images, backs up any existing Openbox configuration, and reloads the running WM. It does not rebuild or reflash the USB. Test screen brightness, keyboard lighting, mute and volume in CocoOS first, then while streaming. If a key sends a function key rather than a media symbol, hold Fn. Volume increase is capped at 100%; use the saved hardware mixer adjustment if speakers remain quiet. Physical keypresses and stream interception must be confirmed on the Mac.
