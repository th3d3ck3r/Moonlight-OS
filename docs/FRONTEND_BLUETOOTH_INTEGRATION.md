# Frontend selection and Bluetooth candidate

This change is a candidate for physical Mac validation. Published as an [experimental prerelease](https://github.com/th3d3ck3r/Moonlight-OS/releases/tag/v0.1-experimental.20261002), alongside the previous repair download.

The tty1 chooser offers Vibemis, Artemis, Pegasus, vanilla Moonlight and CocoOS. Enter or an eight-second timeout retains the saved selection; the initial default is vanilla Moonlight. Change it through settings option 9 or `sudo moonlight-os-client <name>`. Existing settings options 7 and 8 still select CocoOS and Moonlight. The selected client starts inside the existing X11/Openbox session. Launch failures fall back to vanilla Moonlight.

Vibemis 0.5.0 and Artemis are built from exact source commits against Fedora 44. The Vibemis AppImage crashed during CUDA decoder probing in the Fedora test, so it is not shipped. Pegasus alpha16-106-g83fd27f4 is checksum-pinned in SOURCES.lock. No frontend requires FUSE at boot. Pegasus is a launcher with four client entries; pairing a host and choosing its apps takes place inside the selected streaming client. Vibemis and Artemis use separate settings and host credentials; pairing in one does not pre-pair the other.

`moonlight-bluetooth` provides scan/pair, reconnect, disconnect, explicit confirmed forget, AirPods playback modes and adapter diagnostics. Pairing enables the radio and pairability, keeps one KeyboardDisplay agent alive, displays PIN/passkey confirmations, then checks BlueZ's paired, trusted and connected states. Device names are not restricted by brand. Old `dualsense-pair` and `airpods-pair` commands route through this flow. Only Bluetooth-capable controllers with Linux-supported protocols can work wirelessly; USB-only/proprietary radio devices still need their cable or dongle. A successful connection is not a guarantee of every controller feature.

Retained: Intel full iHD decode, English defaults and CocoOS label patch, native Retina display setup, Openbox fullscreen handling, media shortcuts, speaker restore, 100-row console, controller audio suppression, AirPods AAC/SBC policy, root growth, tty2 recovery and strict OVMF marker checks. No minimization plan has been implemented.

Validation covers static payload equality, Bluetooth PTY confirmation/rejection fixtures, false-success prevention, all five selector choices, clean launch environments, Fedora dependency resolution, Artemis compilation and software-rendered X11 startup of the three added frontends. Image inspection requires their installed executables and pinned receipts. OVMF cannot validate the Mac's Bluetooth radio, AirPods sound, hardware decode or live streaming; those require the user's physical test.

## Completed candidate — 2026-10-02

Build [36995905431](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36995905431) succeeded from `32bc89855f8bac3caf90b9d5177ae583bc50313d`. Installed-image inspection and strict OVMF UEFI boot validation passed. All six audits passed for this exact commit in run [36995905423](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36995905423).

Candidate artifact [11223945065](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/36995905431/artifacts/11223945065) contains the compressed raw image and its checksum. The uploaded ZIP is 3,882,747,742 bytes; its SHA-256 is `96554f84507bd04637d6e55a83effc2dfa5a8cc9beecef4a6c62503fa9767554` (this is the ZIP digest, not the image digest). GitHub reports expiry on 2026-10-16.

Physical Mac boot, Bluetooth controller/AirPods pairing and real frontend streaming remain pending user validation. The user authorized experimental publication; the previous repair remains available and this candidate is not promoted as hardware-validated.
