# Crimson Glass verification

This candidate continues the saved WIP checkpoint. The handoff was not treated as a verified build.

## Pass 1 — source and runtime behavior

Recovered the original source and checked the complete patch against clean pinned Vibemis `c3032fc8ee56188a91c1f5a3a8aeae6cf36fb6de`. Reviewed graphs/history locking/reset/fallbacks, sampling leases and wallpaper validation/copy/reset. Corrected bright placeholder artwork, icon alignment, modal scrims, remaining motion transitions and legacy monitor lease behavior.

Static shell/Kickstart, embedded-payload parity, source pins and GPU/media-key fixtures pass. Python BlueZ, Control Center, connection and PTY/frontend-selection fixtures pass. Exact-source build-gate tests reject stale, missing, failed, skipped and pending audits.

## Pass 2 — Qt and layout fixtures

The full focused Qt suite passes 19 tests. Actual PcView/AppView are rendered at 1920×1080, 1280×720 and 900×640 with 100/110/125% text. Tests exercise keyboard grid navigation and rail focus, all sixteen accents, high contrast/reduced motion, the background picker, wallpaper persistence after source deletion, corrupt/oversized image rejection, overlay alpha and 60-sample histories, missing/invalid graph metrics, multiple visible monitor consumers and settings/dialog actions. Quick Menu is loaded and navigated in the fixture. The existing overlay-placement and decoder-status suites pass 7 and 28 tests respectively. Actual screenshots are linked in CRIMSON_GLASS.md; illustrative data is explicitly identified.

QML engine warnings: zero. The pre-existing deliberately failing TLS fixture can produce Qt's internal QNetworkReply warning; its trust/authentication tests pass. This is separate from QML warnings.

## Pass 3 — exact-source Fedora audits

All seven source audits passed for `b687ecd0710a04d73bac62ebab44fe418927d76e`: [audit run](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37126618900). Native Fedora compilation selected FFmpeg, VAAPI and EGL; Eclipse, Artemis and Pegasus remained alive through X11 software-rendered startup. The final image commit is also required to pass all seven audits. The build workflow now blocks installation until those audits succeed. Fixture success does not establish physical hardware support.

## Pass 4 — installed image, UEFI and downloads

Pending. The inspector must match the installed patch/helpers, verify that the complete reviewed patch is applied to the installed pinned source, inspect kernel/EFI/modules/policies, and pass strict OVMF `MOONLIGHT_OS_BOOT_OK` before compression/upload. The new artifact has a distinct Crimson Glass name; the previous System Controls download is preserved.

Comparison build: [System Controls ZIP](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37105853178/artifacts/11268692925), source `4755e352876e48b73521ec28dec9015e514bded2`, expires October 17, 2026.

Physical acceptance remains pending for controller power-off/reconnect, AirPods negotiated codec/latency, Mac-specific sensors/input/audio, all accents on the native display and sustained hardware-decoded streaming. OVMF proves generic UEFI boot only.
