# 🖤🔴 Vibemis Crimson — theme and status update

Status: included in the [new experimental release](https://github.com/th3d3ck3r/Moonlight-OS/releases/tag/v0.2-experimental.20261002). All seven audits, installed-image inspection and strict OVMF boot passed for build 37022392821 / source `ebce257c6429f5b363ba0ec6a17815e524d87f29`. The regular release remains unchanged; physical testing of this candidate is pending.

The Moonlight-OS patch for pinned Vibemis 0.5.0 supplies one mostly-black palette across the launcher, settings, dialogs, popups and existing token-based quick-menu surfaces. Crimson is the default for new preferences. Existing accent indices 0–3 retain their colors; users with saved settings can select Crimson explicitly. Sixteen choices: Teal, Indigo, Green, Amber, Crimson, Red, Orange, Gold, Lime, Mint, Cyan, Blue, Violet, Pink, Silver and Rose. Highlight/pressed colors follow the active accent, including Material controls; existing shapes, typography, focus handling and streaming shortcuts are preserved. No compositor or blur dependency is added.

Three matching header buttons:

- **Network:** active local interfaces, Wi-Fi SSID/signal when NetworkManager supplies it; a live link is not proof of internet access. Local readout refreshes every ten seconds without rescanning Wi-Fi.
- **Battery:** local Mac battery percentage and charging state from sysfs; unavailable hardware is explicitly labeled.
- **Host hardware:** select a PC on the home screen or enter its app list, then open CPU/RAM/GPU/VRAM/temperatures/encoder/network stats supplied by Vibepollo. This is a launcher panel, not a new in-stream overlay. Existing stream statistics and quick-menu behavior remain intact.

## Host stats setup

Enable realtime stats in the installed Vibepollo host. Configure an HTTPS management URL and a scoped read-only bearer token permitting GET `/api/host/stats`; GameStream pairing does not grant management API access. Default management address is the active host's HTTP port plus one (normally 47990); an override supports IPv6 and custom ports.

For a self-signed host, obtain and verify its certificate's SHA-256 fingerprint directly on that host, then paste it into Configure. System certificate validation stays enabled. Only the explicitly matching pinned certificate can tolerate self-signed/hostname errors; expired certificates are not accepted. Changed certificate, unauthorized token, unsupported endpoint, malformed data and unavailable sensors produce a clear message or N/A. No token is sent via a URL, command line, log or cross-origin redirect.

Per-host access is written atomically to a user-only `crimson-hosts.json` in Vibemis's application config directory. Blank token input retains a saved token only when the URL is unchanged; a new host/URL requires its own token. This file is persistent on the USB but not encrypted. Stats poll every two seconds only while the host panel is visible, allow one request at a time, enforce a 64 KiB response limit and a bounded request time, and cancel on close/host change. The displayed timestamp is local receipt time, not a host sampling timestamp.

Generic Bluetooth's initial scan is shortened from twelve to six seconds. Discovery remains paired with a live confirmation agent; retries are available by rescanning, and saved bonds are never automatically deleted.

## Validation and preservation

The reviewed patch is stored in `patches/vibemis-crimson.patch`, SHA-256-pinned in `SOURCES.lock`, embedded offline into Kickstart and verified before application. The image inspector requires its installed receipt. Recovery manifests include the changed Kickstart/lock, preventing reuse of an older installed image.

Four passes: structure/payload/patch checks; focused Qt parser/TLS/palette/panel tests plus Fedora native compilation; installed-payload inspection; strict OVMF boot validation. All four passes completed; installed-image inspection passed at 15:10:20 UTC and OVMF at 15:10:31 UTC. Current physical success belongs to the existing download, not this source revision. New colors/panels, host API setup, Wi-Fi/battery readouts, Bluetooth discovery timing and streaming regression still need a physical test after flashing the new experimental build.

The five-way selector, other clients, Intel decode, native Retina/Openbox session, confirmed Mac media keys, speaker save/restore, 100-row console, AirPods policy, DualSense HID/audio policy, animation, root growth and recovery consoles remain in scope for regression checks. No browser/dashboard launch, graphical appliance settings redesign or OS minimization is included here.

## Next-image source: connection selectors and managed updates

Source commit `766f07849067b7f0b80e2d36f56413a54dd3da90` adds a Wi-Fi selector to the network button and a matching Bluetooth button. These are source changes, not part of the existing download. No image build or release change was started.

- Wi-Fi: open the network button, Scan, select a visible network, and Connect. Enter a requested password in the private prompt. Select a connected network to Disconnect. Hidden and advanced enterprise networks remain available through the diagnostic shell.
- Bluetooth: put the device in pairing mode, open the Bluetooth button, Scan, select it, then Pair / Connect. Enter PINs or type yes/no when BlueZ requests confirmation. Disconnect retains the saved bond; Forget explicitly confirms its removal. The pairing agent stays alive between discovery and pairing while the panel remains open.
- Close the panel to cancel an operation. Scans and helper processes run on demand. Errors offer retry/recovery guidance; no saved bonds are automatically removed.
- Customized Vibemis disables upstream standalone download/replacement and points to Moonlight-OS releases. This does not implement automatic OS image updates.

All seven source audits passed in [run 37084032830](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37084032830), including Fedora native frontend compilation. Six deterministic helper fixtures and ten Qt tests pass, including private credential transport, update replacement prevention, existing TLS/palette tests, and selector rendering at 1024×640. Physical Wi-Fi/authentication and Bluetooth hardware testing remains necessary after an authorized image build. [Feature brainstorm and control-center proposal](VIBEMIS_FEATURE_PLAN.md) remains planning only.
