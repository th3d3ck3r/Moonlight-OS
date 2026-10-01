# Build status

Status: **automatic builds paused for full v0.1 audit**

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

After the paused static audit is complete, one manual GitHub Actions image build is the next gate. Real i915/VA-API, BCM4350, Bluetooth, audio, controller, and streaming behavior must be validated on the actual MacBook; QEMU cannot prove those hardware-specific items.
