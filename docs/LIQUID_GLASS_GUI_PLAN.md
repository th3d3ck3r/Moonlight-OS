# 💎 Crimson Glass — Moonlight-OS interface plan

Status: separate design/implementation proposal, not implemented.
Prepared October 1, 2026. Begin after physical USB boot and basic streaming validation.
Related but independently staged: [host stats overlay and dashboard plan](HOST_OVERLAY_PLAN.md).

## Goal

Make every Moonlight-OS-owned graphical surface feel like one product: clear hierarchy, consistent controls, a restrained glass material, predictable navigation, and readable settings. Use Liquid Glass as visual inspiration, implemented in Qt/SDL on Linux rather than Apple's proprietary material.

**Palette direction: mostly black, with crimson and red highlights.** Use smoky black glass, restrained deep-crimson selection fills, and brighter red focus/action accents. Keep normal reading text near white so the interface stays readable.

Apply the same visual language across CocoOS, the upstream Moonlight fallback, graphical appliance settings, setup/pairing dialogs, and planned host-stat controls. Preserve existing streaming capabilities and a reliable text recovery console.

## What the source actually supports

Inspected pinned CocoOS `8c22132f1ce4146c0d6bff812f6fc8f724fe0101` and Moonlight `8369d1a0e11b999d4d1598f62ca5f6dea49602fb`, plus Moonlight-OS Kickstart:

- CocoOS `app/gui/console/Theme.qml` already centralizes colors, fonts, spacing, motion and a reference 1280×800 canvas. Its current accent is orange, with Sora UI and JetBrains Mono diagnostic fonts.
- `OptionsSheet.qml` and `ConsoleDialog.qml` already implement modal focus, controller/keyboard navigation and safe cancel defaults.
- `SettingsView.qml` uses Qt Quick Controls; the console theme alone does not cover all legacy controls.
- Some console source strings are French; the redesign needs a visible-string English audit, not merely a stylesheet.
- Appliance settings currently use shell menus, nmtui, bluetoothctl and wpctl. They cannot become glass-themed through QML color changes alone.
- In-stream graphics use SDL overlay surfaces rather than the QML home scene. A common style needs a separate lightweight SDL implementation.
- Qt Quick is already installed. The precise Fedora Qt version and availability of QtQuick.Effects/shader tooling must be checked before choosing effects.

Sources: [CocoOS theme](https://github.com/Djingerr/CocoOS/blob/8c22132f1ce4146c0d6bff812f6fc8f724fe0101/app/gui/console/Theme.qml), [settings](https://github.com/Djingerr/CocoOS/blob/8c22132f1ce4146c0d6bff812f6fc8f724fe0101/app/gui/SettingsView.qml), [Kickstart](../config/moonlight-os.ks).

## Visual system — one source of truth

Proposed starting tokens, to refine in actual screenshots:

| Token | Starting specification |
| --- | --- |
| Canvas | Almost-black `#050506`; darken artwork behind controls and avoid large bright backgrounds |
| Material | Smoky black glass: base `#0B0B0E`, raised `#141116`, with strong black fill behind text/forms |
| Primary text | Near white `#F4F6FA`; measure contrast on actual composited backgrounds |
| Secondary text | Neutral gray `#BDB7BE`; never use transparency alone for hierarchy |
| Crimson | Deep crimson `#9F1239` for selected surfaces, restrained gradients and primary button fills with near-white labels |
| Red highlight | Bright red `#FF4D64` for focus rings, active indicators, slider/toggle accents and small highlights |
| Glass rim | Subtle neutral-white upper edge with a faint crimson lower edge; avoid neon outlines on every panel |
| Status | Preserve semantic success/warning/error colors with icon/text; distinguish errors from decorative red by shape, label and placement |
| Spacing | 4/8/12/16/24/32/48 logical-unit scale |
| Corners | 10 small controls, 16 cards, 24 sheets/dialogs; pills only for compact status/navigation |
| Typography | Existing licensed Sora + JetBrains Mono; consistent 14/16/20/28/36 hierarchy |
| Control targets | At least 44 logical units; prefer 48–56 for controller-oriented rows |
| Icons | One bundled SVG family with matching stroke weight and labeled actions |
| Motion | 120–180 ms feedback, 180–240 ms transitions; reduced-motion alternative |

Black remains the dominant surface color; crimson/red mark interaction and hierarchy rather than flooding entire screens. Use a faint crimson glow only around the focused control, no constant pulsing. Default content text is near white, not red. Selected rows use a dark crimson wash plus a visible red focus ring; primary actions use a deep-crimson fill. Disabled controls use neutral gray. Apply the same palette to both clients, settings, dialogs and the planned stats overlay.

Keep text and content clear; reserve stronger glass treatment for navigation bars, sheets, floating controls and selection surfaces. Do not layer translucent cards inside translucent cards indiscriminately. A restrained highlight, thin inner rim and soft shadow establish depth; blur is an optional enhancement, not a prerequisite.

Material modes:
- **Standard:** smoky black glass with restrained crimson/red accents and bounded static/menu background blur where supported and measured.
- **Lightweight:** translucent tint, highlight and border without blur.
- **Opaque / High Contrast:** solid black surfaces, near-white labels and a strong red/white focus outline; preserve the crimson identity without transparency.
- **Reduce Motion:** removes drift, scaling and long animated transitions.

Choose initial defaults using MacBook measurements, and expose the modes in Appearance. Avoid pointer-following reflections, continuous shimmer, animated noise and distortion of text or streamed video.

## Coverage map

| Surface | Cohesive redesign |
| --- | --- |
| CocoOS home/library | Floating status/navigation strip, consistent host card, game focus ring, clean action tray |
| Upstream Moonlight fallback | Same tokens and control family for PC/app grids, menus, toolbars and settings, while preserving its simpler layout |
| Stream settings | Resolution, FPS, bitrate, codec, V-Sync, audio and input groups; all existing advanced settings remain reachable |
| Display settings | Detected outputs, supported modes, scale and brightness where supported; confirmation/revert flow for changes that could blank the screen |
| First boot | Welcome → network → optional Bluetooth/audio → host discovery/pairing; skippable steps and clear connection state |
| Wi-Fi | Scan list, signal/security state, password entry, connect/disconnect, saved networks and existing band preference |
| Bluetooth | Scan, pair, trust/reconnect, disconnect/forget; progress, timeout and unavailable-controller states |
| AirPods/audio | Output selection, volume and existing Latency/Quality preference; explicitly playback-only with no guaranteed latency claim |
| DualSense/input | Pairing instructions, USB/Bluetooth status, diagnostics and controller-audio-disabled explanation |
| Client selection | CocoOS/Moonlight choice, current/default indicator and confirmation before interrupting a session |
| Diagnostics | Readable summary cards plus collapsible monospaced detail, running/success/failure states and export |
| Host management | Host address, pairing/removal, optional stats API setup, certificate trust and planned Open Host Dashboard action |
| Stats overlay | Same typography hierarchy and palette, compact outlined text/solid translucent panel, distinct HOST/CLIENT sections |
| All dialogs | Shared title/body/actions, cancel-first destructive confirmations, focus restoration and consistent errors |
| Recovery console | Keep tty2 usable independently; retain text helpers if graphics, input or networking breaks |

Third-party host web content remains Vibepollo/Sunshine's UI; style our dashboard-launch control and browser helper shell, not promise to theme an external server. Apple firmware startup selection and system boot/recovery text are also outside the application theme.

## Navigation & behavior rules

A single settings entry opens categories: **Streaming, Display, Network, Bluetooth, Audio, Controllers, Hosts, Appearance, Diagnostics, About**. Use a sidebar on wide layouts and a category list on narrow layouts. Consistent breadcrumbs/back navigation and one primary action per screen.

Controller, keyboard and mouse paths must all work. Strong visible focus, no hover-only actions, proper scroll-to-focus, A/Enter to activate, B/Escape to go back, contextual controller glyphs, and focus returned to the originating control when a dialog closes. Do not consume streaming shortcuts unexpectedly.

Editable forms need labels, validation, disabled/busy/error states, password masking with deliberate reveal, and a usable on-screen keyboard when no physical keyboard is available. Test touchpad text entry and Qt input methods. No essential action hidden behind tiny icons.

Use English product text throughout. Avoid raw stack traces in the main flow; provide actionable messages with optional diagnostic details. Test long host names, SSIDs and error messages without clipping.

## Architecture

1. **Shared design package.** Keep tokens and QML primitives under reviewed Moonlight-OS patch assets. Generate both client theme adapters from a single data source so appearance does not diverge. Use shared GlassPanel, ActionButton, SettingRow, Toggle, Slider, ChoicePicker, TextField, StatusBadge, ModalDialog and FocusRing components.
2. **QML material rendering.** Start with inexpensive gradients/borders. If the installed Qt supports it, use QtQuick.Effects MultiEffect for bounded blur/shadow. Explicitly sample only app-owned backdrop layers, avoid recursive/self-capture, share/downsample background captures, cache static output and destroy/hide effects when unused. X11 compositor absence does not prevent effects inside our Qt window; it does prevent assuming system-wide backdrop blur.
3. **Graphical appliance settings.** Add a Qt Quick settings module/app using structured backends: NetworkManager and BlueZ D-Bus for device operations; tested PipeWire/WirePlumber integration or bounded argument-based helper calls for audio; existing verification helpers for diagnostics. Keep operations asynchronous and cancellable, with specific backend errors. Never interpolate SSIDs, passwords or device names into shell commands. Privileged mutations go through narrow reviewed helpers; UI runs as the ordinary user.
4. **First-boot integration.** Current networking setup runs before X11. To provide graphical first boot, start the X11 shell/settings flow even with no saved network, gate client launch until networking or an explicit offline path, and retain tty2 recovery. Preserve root-growth ordering and the boot marker; add tests for offline first boot and Wi-Fi failure.
5. **Streaming boundary.** The QML application relinquishes normal main-thread processing while SDL streaming. Implement compact overlay styling in the existing renderer; do not run a second full QML glass UI or blur live video each frame. Full settings open before/after a stream in version one.
6. **Build persistence.** Keep patches tied to existing source pins; apply before qmake, fail on drift, include assets/resources in builds and installed inspection, and include patch inputs in recovery hashes. Verify shader compiler/runtime compatibility and package size before adding dependencies.

## Staged implementation

### Stage 0 — baseline and visual proof
After physical boot succeeds, capture current screens and latency/resource measurements. Create representative QML previews for Home, Settings, Wi-Fi, Pairing, Error and Stats. Review black/crimson/red consistency and navigation across those screens, including opaque mode; check red highlights against bright game artwork. No OS rebuild needed for an isolated preview.

### Stage 1 — primitives and client screens
Build tokens/components, migrate CocoOS theme/dialogs/home and all standard Qt Quick Controls, then apply the same system to fallback Moonlight. Preserve backend behavior and settings keys. Audit every popup and English string.

### Stage 2 — graphical system settings
Replace normal-use shell menus with GUI pages while retaining their recovery versions. Integrate networking, Bluetooth, AirPods/audio, DualSense, diagnostics and graphical first boot. Display changes require explicit Apply plus timed automatic revert if unconfirmed.

### Stage 3 — optional host features
Connect the separate host telemetry/dashboard work when it is implemented. Reuse the same settings rows, dialogs, trust UI and status states; style the native overlay within its measured budget.

### Stage 4 — validation and delivery
Complete targeted tests first, then one fresh image build with inspection/OVMF. Repeat real hardware tests and compare streaming against the untouched v0.1 baseline. Keep an Appearance reset and a recovery way to select the fallback client.

## Acceptance gates

- Every owned page, dialog, tooltip, control and focus state uses the black/crimson/red shared tokens; no orphaned stock-white dialogs, default blue/orange interaction accents or inconsistent icon families. Semantic status colors and game artwork remain distinct from theme accents.
- Test 1280×800 logical layout, MacBook Retina scaling, 1080p and narrow windows; no clipped text, offscreen dialogs or double scaling from CocoOS Theme.scale.
- Text remains legible on bright/dark artwork; aim for 4.5:1 normal-text contrast and test high-contrast/opaque modes. Measure red labels and focus borders separately; deep crimson is a surface/fill color, not small body text on black.
- Full keyboard/controller traversal, text entry, modal containment, no stuck buttons, proper back/cancel and focus restoration.
- First boot works with no Wi-Fi, invalid password, absent Bluetooth, offline host and graphics failure recovery.
- Existing stream options, pairing, persistence, fallback, AirPods playback-only policy and DualSense audio suppression remain intact.
- Benchmark menu responsiveness at the intended refresh rate; no persistent hidden blur rendering. Compare idle RAM/GPU/thermals to baseline and preserve the under-2-GB idle target.
- Overlay off/on and theme modes produce no reproducible additional stream stutter; retain i915/VA-API, frame pacing and existing decode path.
- Raw image stays below 14,000 MiB, all audits/inspection/OVMF pass, followed by real MacBook verification.
- Host management web page retains its independent authentication and styling; no credentials in UI logs or diagnostic exports.

## Design references

- [Apple Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials): reference for layered controls and accessibility, not an implementation dependency.
- [Qt MultiEffect documentation](https://doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html): assess against the version actually installed; its performance guidance favors limited effect area and bounded blur.

This is a planning document only. It adds no effects, GUI code, packages or image builds to the current validated appliance.
