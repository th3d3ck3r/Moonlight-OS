# Frontend selection and Bluetooth candidate

This change is a candidate for physical Mac validation. Public download links remain unchanged.

The tty1 chooser offers Vibemis, Artemis, Pegasus, vanilla Moonlight and CocoOS. Enter or an eight-second timeout retains the saved selection; the initial default is vanilla Moonlight. Change it through settings option 9 or `sudo moonlight-os-client <name>`. Existing settings options 7 and 8 still select CocoOS and Moonlight. The selected client starts inside the existing X11/Openbox session. Launch failures fall back to vanilla Moonlight.

Vibemis 0.5.0 and Pegasus alpha16-106-g83fd27f4 downloads are checksum-pinned in SOURCES.lock. Artemis is built from its exact source commit against Fedora 44. Vibemis is extracted at image creation and does not require FUSE at boot. Pegasus is a launcher with four client entries; pairing a host and choosing its apps takes place inside the selected streaming client. Each client has independent preferences and pairing credentials.

`moonlight-bluetooth` provides scan/pair, reconnect, disconnect, explicit confirmed forget, AirPods playback modes and adapter diagnostics. Pairing enables the radio and pairability, keeps one KeyboardDisplay agent alive, displays PIN/passkey confirmations, then checks BlueZ's paired, trusted and connected states. Device names are not restricted by brand. Old `dualsense-pair` and `airpods-pair` commands route through this flow. Only Bluetooth-capable controllers with Linux-supported protocols can work wirelessly; USB-only/proprietary radio devices still need their cable or dongle. A successful connection is not a guarantee of every controller feature.

Retained: Intel full iHD decode, English defaults and CocoOS label patch, native Retina display setup, Openbox fullscreen handling, media shortcuts, speaker restore, 100-row console, controller audio suppression, AirPods AAC/SBC policy, root growth, tty2 recovery and strict OVMF marker checks. No minimization plan has been implemented.

Validation covers static payload equality, Bluetooth PTY confirmation/rejection fixtures, false-success prevention, all five selector choices, clean launch environments, Fedora dependency resolution, Artemis compilation and software-rendered X11 startup of the three added frontends. Image inspection requires their installed executables and pinned receipts. OVMF cannot validate the Mac's Bluetooth radio, AirPods sound, hardware decode or live streaming; those require the user's physical test.
