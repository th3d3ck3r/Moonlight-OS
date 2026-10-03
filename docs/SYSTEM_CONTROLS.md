# EclipseOS System Controls and local overlays

The Eclipse Settings page includes a System Controls tab, using the same dark surfaces, rounded controls and dialog headers/footers, text scaling and sixteen accents as the existing interface.

## Connections

The graphical picker and diagnostic Bluetooth script share a BlueZ D-Bus backend. Device lists come from a single bulk snapshot, and a ten-second discovery updates the picker as devices appear. Discovery is stopped on completion or cancellation. Missing adapters, disabled radios and empty discovery results have explicit messages.

Pairing retains the interactive agent for confirmation and PIN prompts. A successful bond is followed by trust, connection and service-resolution checks. Gaming controllers also require a matching local input device before being reported ready. Failed connection does not erase a saved bond: wake the controller and use Reconnect. Physical controller power-off behavior still requires testing on the target Mac.

## Controls

Available controls include Wi-Fi/Bluetooth radios, audio output/volume/mute, test tone, AirPods audio preference, screen and keyboard brightness, display resolution/refresh, idle blanking, pointer acceleration, natural scrolling and tap to click. Unsupported hardware controls remain disabled. Display changes revert after fifteen seconds unless confirmed, including cancellation of the helper.

The frontend selector applies on the next launch. Frontend restart, reboot and shutdown require confirmation; the recovery console remains available. Pointer and idle choices apply to the current X11 session. Report export remains redacted and private.

## Local hardware monitor

Readings come from local read-only kernel interfaces: CPU utilization and clock, RAM/swap, CPU temperature/fan, exposed GPU utilization, Eclipse process video-engine utilization, default-route network traffic, battery and USB/root storage. Rates require a second sample. Missing sensors display Unavailable. Intel shared GPU memory is system RAM; process video-engine load is not total GPU load.

The local streaming overlay is optional. Its fields, detail, corner, opacity and refresh interval are saved. Ctrl+Alt+Shift+H toggles it during streaming; Ctrl+Alt+Shift+S retains the stream-statistics shortcut. Both overlays use rounded native panels and the selected accent. If both select the same corner, the local panel moves to the opposite horizontal corner. Low-resolution streams and unusually long detailed statistics still need physical review.

## Verification limits

Fixture tests cover enumeration, progress, cleanup, strict action selection, display rollback, metric counters and missing data. Qt tests render the panels at 100%, 110% and 125% text size and verify all sixteen palette colors against native overlay colors. These checks do not establish real Bluetooth firmware behavior, sensor availability, controller power management or sustained streaming performance.
