# Fixed-base EclipseOS updates — included in the new image

The [all-changes image](STREAMING_BUILD_VERIFICATION.md) includes the terminal updater, helpers, launcher and offline recovery unit. Every prepared change through `64ec8f6` is built into exact source `cf58cb9`. The previous Crimson Glass and comparison downloads remain preserved. No production signing identity/feed, deployable signed update package or live Mac installation was created by the build. Subsequent [software/connection work](STREAMING_SOFTWARE.md) is also included.

## Scope and kernel lock

Keep the existing Fedora 44 / MacBookPro14,1 foundation and **6.19.10-300.fc44.x86_64** kernel. The image already excludes the runtime kernel packages from DNF upgrades. The updater additionally refuses staging and activation on a different kernel/architecture/base receipt. Boot recovery can restore the previous files even when the running kernel differs.

| Update target | Permitted destination / behavior |
| --- | --- |
| `frontend` | Native x86_64 Eclipse executable in a new root-owned slot; original AppRun/binary retained |
| `system-controls`, `control-center` | The two existing Python helpers under `/usr/local/libexec/moonlight-os/` |
| `bluetooth-menu` | `/usr/local/bin/moonlight-bluetooth` |
| `streaming-tune` | `/usr/local/bin/eclipseos-streaming`; reversible user-owned presets and diagnostics |
| `wifi-menu` | `/usr/local/bin/moonlight-wifi` |
| `wifi-config` | Existing NetworkManager file; only `connection.wifi.powersave` (2 or 3) |
| `bluetooth-config` | Existing BlueZ main.conf; only `General.AutoEnable` (true or false) |

System payloads require the exact **before SHA-256** exported from the receiving installation. A locally edited file causes rejection. Credentials, saved networks, Bluetooth bonds, pairing keys, user settings, backgrounds and game data are outside the target list. Packages cannot declare paths, commands, service names, package installs or reboot actions. Only the two fixed networking services can be restarted, and only if previously active.

Kernel, modules, drivers, firmware, bootloader, partition layout, library/RPM upgrades, updater self-updates and trust-key rotation are deliberately outside this first version. A Wi-Fi/Bluetooth issue in a helper or the permitted settings can be fixed here; a driver/firmware defect needs a separate validated base release. Signed helper code is trusted executable code: keep the private signing key offline and review every change before signing. This does not harden the development image's existing unrestricted sudo policy.

## One-time public-key enrollment (not performed by this build)

The previous Crimson Glass image predates the updater; the new all-changes image already contains it. Both require owner public-key enrollment. Copy a reviewed checkout of the new image source (or a trusted descendant) onto the USB installation. Stop streaming before enrollment. On the signing machine, create an Ed25519 key with OpenSSL and retain the private key there; transfer **only the public PEM** to the Mac. Do not place a private key in this repository or an Actions artifact.

From that trusted checkout on the supported Crimson Glass or new all-changes Mac installation:

```sh
sudo scripts/bootstrap-updater.sh /absolute/path/to/public.pem
```

Bootstrap checks the exact current base kernel, product/target metadata, pinned Vibemis commit and shipped Crimson patch checksum. It installs the root helper, launcher, tty menu and boot recovery unit, preserving the old launcher. Repeating enrollment with a different key is refused. It does not stage/apply an update or rebuild the OS. Do not enroll an unrelated/older image by changing those checks.

The new image contains the helper/menu/unit/receipt but has **no signing key by default**, so network updates fail closed until the owner enrolls the public key. This build has not created or enrolled a production signing key.

## Using updates

Use **Ctrl+Alt+F2** for tty2, then run `eclipseos-updates`. The new image's settings menu also offers **u) EclipseOS updates**. This interface is independent of Eclipse's GUI/networking. The existing in-app upstream updater stays disabled; embedding this new workflow in the graphical settings is a later UI task.

1. Check stable or testing, then stage. This verifies the signature, download size and checksum, every archive entry and every file checksum before marking anything pending. Staging changes neither live helpers nor services.
2. End the stream and close all frontends. Apply from tty2 or relaunch a frontend normally; the launcher applies the pending update before starting a client. It refuses explicit activation if another frontend is running; automatic launch preflight defers it, preserving Pegasus launching child clients. Network/Bluetooth configuration changes can temporarily disconnect devices.
3. Test Eclipse, Wi-Fi and Bluetooth, then select **Confirm tested trial** in tty2 and type `KEEP`. Until confirmed, the next launch or boot restores the previous files/slot offline. A new Eclipse process that exits with an error triggers recovery and starts the preserved baseline executable. A hang requires tty2 intervention; there is no claimed automatic hang detection.
4. Explicit rollback remains available after confirmation until another update reaches snapshot creation. Stop all frontends before rollback. Cancel clears a pending selection without applying it. Update IDs are unique; a cancelled/staged ID is not reused.

CLI equivalents (all JSON output):

```sh
sudo /usr/local/libexec/moonlight-os/eclipseos-update.py status
sudo /usr/local/libexec/moonlight-os/eclipseos-update.py baseline > baseline.json
sudo /usr/local/libexec/moonlight-os/eclipseos-update.py check testing
sudo /usr/local/libexec/moonlight-os/eclipseos-update.py stage testing
sudo /usr/local/libexec/moonlight-os/eclipseos-update.py apply
sudo /usr/local/libexec/moonlight-os/eclipseos-update.py confirm
sudo /usr/local/libexec/moonlight-os/eclipseos-update.py rollback
```

If networking is unavailable, copy a signed package folder via another machine/USB and use `stage-offline /absolute/folder`. It requires `manifest.json`, the raw 64-byte `manifest.sig`, and `payload.tar.gz`; verification is identical to online updates. The baseline export contains only the base identity, kernel and helper/config hashes, not network credentials.

Recovery uses a durable write-ahead journal and checksum-protected backups under root-only `/var/lib/eclipseos-updates`. Activation writes each destination atomically, preserving file modes; the entire group is recovered through the journal rather than claimed to be one filesystem-atomic operation. Recovery runs before networking/getty at boot and never downloads anything. If restoring/restarting fails, the journal remains for retry; keep tty2 and the preserved image available. Do not delete state directories to clear an error.

## Preparing a later release without rebuilding the OS

For frontend changes, build **only Eclipse** from the pinned Vibemis source plus the complete current production patch, using the existing Fedora 44 native audit recipe/dependencies. Retain X11, FFmpeg, VA-API, EGL, SDL and native overlay checks. Use the resulting `usr/bin/vibemis` executable as the frontend input, not an upstream AppImage. For helper/config-only releases, no native frontend compile is needed. This implementation never compiles during package creation.

Export a fresh baseline from the intended Mac installation. Review the release notes and changed files, run source tests, then build/sign a package on the offline signing machine:

```sh
python3 scripts/make-update-package.py \
  --id eclipse-testing-001 --sequence 1 --channel testing \
  --source FULL_40_CHARACTER_SOURCE_COMMIT \
  --notes /absolute/release-notes.txt --baseline /absolute/baseline.json \
  --key /absolute/offline-private.pem \
  --url https://github.com/th3d3ck3r/Moonlight-OS/releases/download/eclipse-testing-001/payload.tar.gz \
  --file system-controls=/absolute/reviewed/system-controls.py \
  --output /absolute/new-package-folder
```

Add `--file frontend=/absolute/prebuilt/vibemis` and/or other allowlisted targets as appropriate. The packager refuses an existing output folder, unknown targets and duplicate targets. It signs the exact manifest bytes with Ed25519; the manifest binds the release source, notes, channel, sequence, base, archive checksum/size and file metadata.

Publish the payload under its immutable release ID in this repository. Publish the identical manifest/signature as assets at `eclipseos-updates-testing` (or `eclipseos-updates-stable` after acceptance). These feed tags/assets do not yet exist as part of this preparation. Per-channel accepted sequence numbers prevent silent downgrade/replay; rollback remains a separate explicit operation. Hosting assets alone does not make an unsigned update installable. Package downloads allow HTTPS GitHub release/CDN destinations only, with bounded sizes/timeouts and no proxy inheritance.

## Validation and remaining gates

Source checks: `bash scripts/validate.sh`, `python3 scripts/audit-runtime.py`, and the dedicated updater tests. `updater-source.yml` is a prepared manual workflow containing source checks only; it has not been dispatched. See [source verification](UPDATER_VERIFICATION.md). Test bundles and ephemeral keys live in disposable test directories; they are not deployable releases.

Before enabling the first real feed: provision an owner-controlled public key, run the existing native Qt/frontend and decoder checks for any frontend changes, test bootstrap/apply/confirm/rollback on a disposable copy of the current image, then test tty2 recovery, reboot interruptions, Wi-Fi reconnect and Bluetooth/controller reconnect on the Mac. Source tests do not establish physical acceptance or power-loss guarantees for a particular USB/controller. The all-changes image has since been built and verified; future frontend payloads must pass native checks on their own exact source.
