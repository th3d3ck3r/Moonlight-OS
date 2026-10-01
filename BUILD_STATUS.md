# Build status

Status: **image build not yet completed**

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

The GitHub Actions image build is the next gate. Real i915/VA-API, BCM4350, Bluetooth, audio, controller, and streaming behavior must be validated on the actual MacBook; QEMU cannot prove those hardware-specific items.
