# Test plan — MacBookPro14,1

Regular release: [Apollo/frontends/Bluetooth](https://github.com/th3d3ck3r/Moonlight-OS/releases/tag/v0.1-experimental.20261002), with user-confirmed Mac boot, animation and Bluetooth pairing. New experimental candidate: [Vibemis Crimson](releases/v0.2-experimental.20261002.md); build 37022392821 and all seven exact-source audits passed, including inspection and OVMF. Its physical checks below remain required. See [host-stats setup](VIBEMIS_CRIMSON.md).

## Gate 0: automated image/UEFI preflight

Before any physical USB test, CI must pass both `scripts/inspect-image.sh` and `scripts/test-ovmf.sh`.

Require:

- GPT contains EFI, /boot, and XFS root partitions.
- `EFI/BOOT/BOOTX64.EFI` exists.
- CocoOS, upstream Moonlight, Vibemis, Artemis, Pegasus, selector/launcher/Bluetooth helpers, pinned receipts, and audio policies are present in the installed root.
- QEMU/OVMF boots the raw image and the guest emits `MOONLIGHT_OS_BOOT_OK` after reaching the multi-user boot path.
- The OVMF test uses a qcow2 overlay so the release raw image remains unchanged.
- The first-boot root expansion service must either grow the XFS root partition or explicitly detect NOCHANGE; other failures must remain retryable.
- Installed-image inspection must find i915, Apple SPI, brcmfmac, hid-playstation, Intel iHD VA-API, and the built Cirrus CS8409 module for the pinned kernel.

## Gate 1: boot and platform

1. Flash the `.raw.xz` image to a **16 GB-or-larger USB drive**.
2. Hold Option at power-on and confirm **EFI Boot** appears.
3. Boot the USB without mounting or modifying the internal SSD.
4. Confirm `cat /sys/class/dmi/id/product_name` is `MacBookPro14,1`.

## Gate 2: hardware

Run `sudo moonlight-os-verify` and require:

- `i915` available, bound to the Intel DRM device, with its discovered card and render node (the tested Mac used `card1` and `renderD128`; do not require `card0`).
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

## Gate 3: frontend selection and client comparison

Test the same Vibepollo host and stream settings using:

1. Upstream Moonlight.
2. CocoOS.
3. Vibemis.
4. Artemis.
5. Pegasus: launch each of its four client entries and repeat the streaming tests inside that client.

Verify initial Moonlight default, all five boot selections, Enter/eight-second saved selection, settings option 9, reboot persistence and launch-failure fallback. Pair the host separately in each client. Check English labels and native Retina/fullscreen sizing.

Start at 1920×1080, 60 FPS, H.264, 30–50 Mbps, hardware decode, V-Sync on, frame pacing on.

Record network latency, decode time, render time, dropped frames, and visible frame-time spikes. Repeat with HEVC and then Wi-Fi vs Ethernet.

## Gate 3b: splash and generic Bluetooth

- Confirm Crimson Apollo appears without artificial delay, Escape reveals details and splash ends before networking/X11. Test one-time text recovery and tty2.
- Pair DualShock 4, DualSense and AirPods Pro 2 independently through `moonlight-bluetooth`; respond to confirmation/PIN prompts. Test rejection, retry, disconnect/reconnect and confirmed forget without deleting other bonds.
- Verify controller input, AirPods playback/codec, reboot reconnection and radio recovery on the real Mac. A fixture connection state is not a hardware result.
- Test volume, mute, display and keyboard brightness both in the UI and during streaming; check no duplicate key handling.

## Gate 3c: Vibemis Crimson experimental

- On fresh preferences, confirm Crimson is selected; an existing accent is preserved. Select all sixteen accents and check launcher, settings, help, dialogs, popups and quick-menu controls share the dark palette and active accent.
- Check the three header icons at native Retina resolution and smaller window widths; keyboard/controller focus must still reach every existing header button and page.
- Compare network icon/readout against NetworkManager, connected/disconnected Wi-Fi and an offline link. Compare battery percentage/charging state against the Mac; missing sensors must show unavailable.
- Select a host and configure its HTTPS management URL, a read-only token scoped to GET `/api/host/stats`, and a verified certificate fingerprint when self-signed. Compare CPU, RAM, GPU, VRAM, encoder, temperatures and network values with Vibepollo. Missing metrics must show N/A.
- Close the host panel and verify requests stop. Reopen, switch hosts, disconnect networking, reject/change the certificate, and test an unsupported Sunshine host; ensure clear errors and no stale values or forwarded credentials.
- Reboot and confirm per-host access persists privately. Stream normally with the panel closed, check no extra input latency, and repeat existing streaming/quick-menu/Intel/media-key tests.
- Compare the shorter six-second initial Bluetooth scan with pairing and rescan of the actual controllers/AirPods.

## Gate 4: stability

- 30-minute Desktop stream.
- 30-minute game stream with controller.
- Disconnect/reconnect ten times.
- Reboot five times and confirm Wi-Fi/Bluetooth/pairing persist.
- Confirm CocoOS crash/exit falls back to upstream Moonlight after three consecutive failures.

## Success criterion

Linux is the preferred permanent client only if it matches the low input latency observed under Windows on this MacBook while eliminating or materially reducing the periodic stutter.
