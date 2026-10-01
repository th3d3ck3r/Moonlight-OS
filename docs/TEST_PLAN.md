# Test plan — MacBookPro14,1

## Gate 1: boot and platform

1. Flash the `.raw.xz` image to an 8 GB-or-larger USB drive.
2. Hold Option at power-on and confirm **EFI Boot** appears.
3. Boot the USB without mounting or modifying the internal SSD.
4. Confirm `cat /sys/class/dmi/id/product_name` is `MacBookPro14,1`.

## Gate 2: hardware

Run `sudo moonlight-os-verify` and require:

- `i915` available and `/dev/dri/renderD128` present.
- VA-API advertises H.264 and HEVC decode profiles.
- `brcmfmac` available and NetworkManager sees Wi-Fi.
- Bluetooth controller visible after any required one-time SMC reset.
- MacBook Cirrus audio driver loaded and a PipeWire sink exists.
- USB and Bluetooth gamepads appear as input devices.

## Gate 3: client A/B

Test the same Vibepollo host and stream settings using:

1. CocoOS.
2. Upstream Moonlight.

Start at 1920×1080, 60 FPS, H.264, 30–50 Mbps, hardware decode, V-Sync on, frame pacing on.

Record network latency, decode time, render time, dropped frames, and visible frame-time spikes. Repeat with HEVC and then Wi-Fi vs Ethernet.

## Gate 4: stability

- 30-minute Desktop stream.
- 30-minute game stream with controller.
- Disconnect/reconnect ten times.
- Reboot five times and confirm Wi-Fi/Bluetooth/pairing persist.
- Confirm CocoOS crash/exit falls back to upstream Moonlight after three consecutive failures.

## Success criterion

Linux is the preferred permanent client only if it matches the low input latency observed under Windows on this MacBook while eliminating or materially reducing the periodic stutter.
