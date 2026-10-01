# Test plan — MacBookPro14,1

## Gate 0: automated image/UEFI preflight

Before any physical USB test, CI must pass both `scripts/inspect-image.sh` and `scripts/test-ovmf.sh`.

Require:

- GPT contains EFI, /boot, and XFS root partitions.
- `EFI/BOOT/BOOTX64.EFI` exists.
- CocoOS, upstream Moonlight, settings/diagnostic helpers, and audio policies are present in the installed root.
- QEMU/OVMF boots the raw image and the guest emits `MOONLIGHT_OS_BOOT_OK` after reaching the multi-user boot path.
- The OVMF test uses a qcow2 overlay so the release raw image remains unchanged.

## Gate 1: boot and platform

1. Flash the `.raw.xz` image to a **16 GB-or-larger USB drive**.
2. Hold Option at power-on and confirm **EFI Boot** appears.
3. Boot the USB without mounting or modifying the internal SSD.
4. Confirm `cat /sys/class/dmi/id/product_name` is `MacBookPro14,1`.

## Gate 2: hardware

Run `sudo moonlight-os-verify` and require:

- `i915` available, bound to the Intel DRM device, with both `/dev/dri/card0` and `/dev/dri/renderD128`.
- VA-API H.264 and HEVC profiles visible over the DRM render node.
- OpenGL/Mesa and Vulkan diagnostic stacks installed; `igt-gpu-tools` is the current Fedora updates build and `intel_gpu_top` can observe GPU/video-engine activity during a stream.
- VA-API advertises H.264 and HEVC decode profiles.
- `brcmfmac` available and NetworkManager sees Wi-Fi.
- Bluetooth controller visible after any required one-time SMC reset.
- MacBook Cirrus audio driver loaded and a PipeWire sink exists.
- Apple SPI keyboard and trackpad appear in the Linux input subsystem.
- Xorg has the `xorg-x11-drv-libinput` driver installed.
- External USB/Bluetooth mouse and keyboard appear as evdev/libinput devices.
- USB and Bluetooth gamepads appear as input devices.
- Brightness/backlight and battery sysfs interfaces are accessible.
- `thermald` is enabled for sustained streaming loads.
- DualSense is detected over USB with `hid-playstation`.
- Pair a DualSense over Bluetooth and confirm it reconnects after reboot.
- Run `dualsense-check` and confirm no driver/tool failures.
- Connect DualSense over USB and confirm its speaker/microphone audio card is **absent from PipeWire**, while controller input still works.
- Pair AirPods Pro 2 through the guided menu; confirm they reconnect after reboot.
- Confirm AirPods expose playback A2DP only and no headset/microphone profile.
- Compare AirPods **Low Latency** and **Quality** modes during a stream.

## Gate 2b: recovery console

- Switch to `Ctrl+Alt+F2`.
- Confirm the default terminal is black with red foreground text.
- Confirm no shell interaction is required for normal appliance boot after networking is configured.

## Gate 2c: live X11 acceleration/input

With CocoOS or Moonlight running on X display `:0`, run `sudo moonlight-os-verify` from tty2. The X11 runtime verifier must confirm:

- OpenGL renderer identifies the Intel/Mesa stack, not llvmpipe/software rendering.
- At least one connected display is visible through `xrandr`.
- Keyboard is visible through XInput.
- A pointing device (Apple trackpad or external mouse) is visible through XInput.
- `intel_gpu_top` shows GPU/video engine activity during an active Moonlight stream.

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
