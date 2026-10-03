# 🌘 Eclipse — EclipseOS frontend

Eclipse is the EclipseOS customization of pinned Vibemis 0.5.0. The public name, app/window icon, welcome screen, installed desktop entry, Steam artwork and visible client text use Eclipse. The internal executable, Qt settings namespace, desktop ID and source pins remain compatible, preserving existing pairing, preferences, shortcuts and launcher recovery. About retains upstream credit and licenses.

## Control center

Use the matching sliders icon in the header or **Ctrl+Shift+C** from the launcher/app list. This first control center is launcher-only; the existing streaming Quick Menu continues to handle in-stream controls and input capture.

- Wi-Fi and Bluetooth selectors reuse the reviewed scan/connect/pair/disconnect/confirmed-forget path.
- Speaker volume/mute and audio-output selection use existing WirePlumber tools. Volume is capped at 100%.
- Screen and keyboard brightness use discovered hardware. Screen controls retain a 5% floor; keyboard lighting can be off. Unavailable hardware is disabled.
- Host tools expose stats, Wake-on-LAN from the host list, and the host management address. A management-launch button is enabled only when a local browser exists; no browser is bundled.
- Named stream profiles save resolution, FPS and bitrate globally or for the selected host. Apply explicitly before a stream; they never silently override codecs, HDR or decoder settings. Desktop and low-bandwidth presets are conservative quick choices. Existing Settings retains full streaming/audio/controller options and settings backup/import.
- Appearance provides 100%, 110% and 125% token-based text sizes, higher contrast and reduced motion for the control center, cards and online-status pulses. Existing sixteen accents continue to affect all token and Material surfaces.
- Support report exports bounded, redacted hardware availability and kernel details to `~/.local/state/moonlight-os/eclipse-diagnostics.json` with user-only permissions. It excludes host tokens, passwords, addresses and device names.
- Restart/shutdown require explicit confirmation. Suspend is deliberately not exposed until physical hardware validation.
- About shows the installed OS version/target, Fedora and kernel, frontend version, upstream credit and **Made by Th3D3ck3r**. Candidate metadata is `0.3-dev`; it does not relabel existing published images.

Helpers run on demand and stop on panel close. They use fixed argument vectors and private JSON pipes; no password is placed in a command line. Closing one panel before opening another prevents helper ownership races.

## Black/crimson glass-inspired design

Existing shape/typography tokens, outline icons and focus states remain the design source. Added action buttons use the same rounded control radius, dark surfaces and active accent; subtle highlights suggest glass without introducing a compositor or blur dependency. Opaque panels preserve readability and performance. Text sizes use bounded shared tokens.

The Eclipse app mark is original vector artwork, with minimal crimson illumination around a black lunar disk. The new native boot animation uses the same mark, one small orbital light and creator credit; the proven password/question/message/quit hooks are retained. Internal Plymouth paths stay compatible. Preview: [boot animation](../assets/boot/crimson-apollo/preview.gif).

## Feature roadmap and limits

[The full feature brainstorm](VIBEMIS_FEATURE_PLAN.md) remains an implementation roadmap, not a claim that every optional idea ships. Existing launcher/Settings already supplies host discovery/pairing/rename/Wake-on-LAN, detailed streaming settings, controller navigation, compact stream statistics, reconnect settings and backup/import. This revision adds the control-center and branding work above.

Remaining optional work includes graphical hidden/enterprise Wi-Fi setup, controller mapping/test tools, per-app automatic profiles, power/lid presets, local controls inside a captured stream, a Vibepollo hardware overlay and signed custom-app updates. These need separate capability/physical validation; unsupported actions must not be simulated or enabled to make the UI appear complete.

## Validation and candidate build

Validate structure and payload parity, deterministic hardware fixtures, native frontend compilation, Qt rendered layouts/profile isolation, native Plymouth prompt/resize hooks, and existing GPU/audio/input/media-key regressions. After those pass, an authorized candidate image must pass read-only installed-payload inspection and strict OVMF boot. Keep regular/experimental release links unchanged until the user validates the Mac image.

Physical checks: speaker/AirPods routing and volume; both brightness controls and all media keys; Wi-Fi credentials and Bluetooth prompts; controller/keyboard focus; launcher scaling at native Retina resolution; actual hardware decode/stream latency; saved profiles after reboot; power confirmation and shutdown. OVMF does not establish Mac hardware success.
