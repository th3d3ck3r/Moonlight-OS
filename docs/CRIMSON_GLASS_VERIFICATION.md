# Crimson Glass verification

This candidate continues the saved WIP checkpoint. The handoff was not treated as a verified build.

## Pass 1 — source and runtime behavior

Recovered the original source and checked the complete patch against clean pinned Vibemis `c3032fc8ee56188a91c1f5a3a8aeae6cf36fb6de`. Reviewed graphs/history locking/reset/fallbacks, sampling leases and wallpaper validation/copy/reset. Corrected bright placeholder artwork, icon alignment, modal scrims, remaining motion transitions, legacy monitor lease behavior, unnecessary wallpaper reloads on dimming/text changes, and transparent title bands exposing scrolled cards.

Static shell/Kickstart, embedded-payload parity, source pins and GPU/media-key fixtures pass. Python BlueZ, Control Center, connection and PTY/frontend-selection fixtures pass. Exact-source build-gate tests reject stale, missing, failed, skipped and pending audits.

## Pass 2 — Qt and layout fixtures

The full focused Qt suite passes 19 tests. Actual PcView/AppView are rendered at 1920×1080, 1280×720 and 900×640 with 100/110/125% text. Tests exercise keyboard grid navigation and rail focus, all sixteen accents, high contrast/reduced motion, the background picker, wallpaper persistence after source deletion, stable image sources while dimming/text size changes, corrupt/oversized image rejection, overlay alpha and 60-sample histories, missing/invalid graph metrics, multiple visible monitor consumers and settings/dialog actions. Pixel comparisons verify that scrolling leaves the title band unchanged at every size and text scale; a negative control using the old transparent header fails that assertion. Quick Menu is loaded and navigated in the fixture. The existing overlay-placement and decoder-status suites pass 7 and 28 tests respectively. Actual screenshots are linked in CRIMSON_GLASS.md; illustrative data is explicitly identified.

QML engine warnings: zero. The pre-existing deliberately failing TLS fixture can produce Qt's internal QNetworkReply warning; its trust/authentication tests pass. This is separate from QML warnings.

## Pass 3 — exact-source Fedora audits

All seven corrected-source audits passed for `615e06f5408709268594187d496b3852c6c59677`: [audit run](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37131400594). This includes the stable wallpaper-source and header pixel assertions. Native Fedora compilation selected FFmpeg, VAAPI and EGL; Eclipse, Artemis and Pegasus remained alive through X11 software-rendered startup. All seven exact image-source audits also passed for `6f1ce48caa3085cae4b625e7c4ac580f4a6fec48`: [final audits](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37132195948). The gate logged their success at 15:19:16 UTC before installation. Fixture success does not establish physical hardware support.

## Pass 4 — installed image, UEFI and downloads

[Image run](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37132195854) succeeded for `6f1ce48caa3085cae4b625e7c4ac580f4a6fec48`. Installed-image inspection passed at **15:45:23 UTC** and strict OVMF passed at **15:45:34 UTC**, before compression/upload. The inspector compared installed helpers and the complete patch byte for byte, confirmed pinned source `c3032fc8ee56188a91c1f5a3a8aeae6cf36fb6de`, and reverse-checked the complete patch against that installed source. Kernel/initramfs/modules, EFI path, client/assets, policies and recovery checks passed. OVMF required the real `MOONLIGHT_OS_BOOT_OK` through a disposable qcow2 overlay; it did not modify the release image.

Complete patch SHA-256: `c7b47a846f7c449b225a811d2a89fc3e98c5f4a0fe40945a27560456bf16cbbf`. Source lock and embedded offline payload match.

**[Download verified automated build](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37132195854/artifacts/11277957881)**. Artifact `11277957881` is `4,106,276,925` bytes / 3.82 GiB and expires `2026-10-17T16:08:06Z`. Upload logs confirm two files: `eclipseos-crimson-glass-mbp14-1.img.xz` (`4,106,276,448` bytes) and `eclipseos-crimson-glass-mbp14-1.img.xz.sha256`. XZ listing confirms raw size `13,147,045,888` bytes / 12.24 GiB, within the conservative 16 GB drive limit.

Compressed image SHA-256: `2f898cd62936c086618011b32ea569c799cfa598f308b23073a705865aa53720`. ZIP artifact SHA-256 (a separate digest): `e43b1f2f388547cd685fb2077b84edfe801b9dd8c1d582b12e371eab051378ca`. Run `sha256sum -c eclipseos-crimson-glass-mbp14-1.img.xz.sha256` in the extracted folder before flashing. The GitHub artifact metadata and upload/job logs were checked; the multi-gigabyte ZIP was not downloaded locally. The corrected UI-preview ZIP was downloaded, matched its published digest, and passed ZIP integrity checks. Gallery files have matching repository blob hashes.

Intermediate runs `37127349549` and `37130627377` were superseded after further review. They are not the completed download.

Comparison build: [System Controls ZIP](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37105853178/artifacts/11268692925), source `4755e352876e48b73521ec28dec9015e514bded2`, expires October 17, 2026.

Physical acceptance remains pending for controller power-off/reconnect, AirPods negotiated codec/latency, Mac-specific sensors/input/audio, all accents on the native display and sustained hardware-decoded streaming. OVMF proves generic UEFI boot only.
