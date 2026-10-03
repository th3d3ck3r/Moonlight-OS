# All-changes streaming/updater image verification — October 3, 2026

Exact image source: `cf58cb9fde3167a68e392e773c7b92ce97db98b1`, including every prepared change through `64ec8f6dc04e1aef898460082cb2ca5e662d5cd6`.

[Verified image download](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37154967013/artifacts/11287150142) · [Image build](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37154967013) · [Exact-source audits](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37154966989) · [Fresh native UI previews](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37154966989/artifacts/11285570733).

## Four verification passes

| Pass | Evidence | Result |
| --- | --- | --- |
| Source/helper contracts | Static/payload/runtime audits and real helper protocols | 100 Python tests pass, including 35 updater fault/rollback tests, real D-Bus serialization and real Wi-Fi PTY authentication |
| Native source | All seven required jobs on exact image source | 19 Qt UI tests and 31 decoder-status tests pass; full Fedora frontend compilation/startup passes, including patched EGL and overlay code |
| Installed image | Read-only inspector at 2026-10-03T22:06:03Z | Installed helper, updater, recovery unit, complete patch/pinned source and runtime payload checks pass |
| Boot and artifact | Strict OVMF at 2026-10-03T22:06:16Z; checksum preparation/upload | UEFI boot gate passes before compression/upload; archive metadata and matching basename checksum verified |

The image gate recorded all seven source audits at **2026-10-03T21:34:54Z**, before installation. Full Fedora compilation selected FFmpeg, VA-API, EGL and Vulkan/libplacebo. Eclipse, Artemis and Pegasus remained alive through X11 software-rendered startup; that verifies loading, not Intel hardware presentation or sustained streaming. Root-growth, OVMF tool preflight, Cirrus audio compilation and native boot-animation checks also pass.

OVMF requires the real `MOONLIGHT_OS_BOOT_OK` marker through a disposable qcow2 overlay. Generic UEFI boot is not physical Mac hardware acceptance.

## Download and checksum

- Artifact **11287150142**, **3,946,847,629 bytes / 3.68 GiB**, expires **2026-10-17T22:27:42Z**.
- Contains `eclipseos-crimson-glass-mbp14-1.img.xz` (**3,946,847,152 bytes**) and its matching `.sha256` file.
- Raw image **13,147,045,888 bytes / 12.24 GiB**; use a **16 GB or larger drive**.
- Compressed-image SHA-256: `68148f0c57328de531da7f721ddb13d038da06730284ce33d078424f43bf1911`.
- ZIP artifact SHA-256: `b4312bd0d32c37895d6b32f050e8347fd90cbf0a108991213a57074250176080`.

Run `sha256sum -c eclipseos-crimson-glass-mbp14-1.img.xz.sha256` in the extracted folder before flashing. GitHub may require sign-in. Job logs and artifact metadata were checked; the multi-gigabyte archive was not downloaded locally.

[Previous Crimson Glass](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37132195854/artifacts/11277957881) and [System Controls comparison](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37105853178/artifacts/11268692925) remain preserved and were confirmed unexpired.

## Scope and limits

The image includes the complete Crimson Glass theme, selectable background and graphs; corrected Wi-Fi/BlueZ helpers; fixed graph-lock contention and EGL swap-request status; reversible streaming/renderer comparisons and private pipeline/driver diagnostics; and the signed frontend/helper updater with tty2/offline recovery. Kernel/base source pins remain fixed.

The updater has no owner public signing key or release feed by default. Enrollment and a signed release are required before network updates can operate. No private key is shipped.

Physical Mac pacing improvement, combined-band Wi-Fi and Bluetooth acceptance, and real installed update/confirm/reboot/rollback acceptance remain pending. Decoder-side overlay refresh still samples hardware synchronously; the graph-lock fix does not remove that decoder dependency. Diagnostic render counters count calls, not physical scanout timestamps. See [software testing](STREAMING_SOFTWARE.md) and [updater enrollment](UPDATES.md).

The fresh native preview archive contains actual rendered fixture views, not physical Mac metrics. It expires **2026-10-06T21:25:30Z**. Its ZIP metadata SHA-256 is `798314589ca27378b8034562f78de00e28a66198ab9bdfadeec8da04c77b024a`; it was not downloaded locally in this verification.
