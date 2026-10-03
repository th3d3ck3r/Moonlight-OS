# 🌑🚀 Crimson Apollo boot animation

The source recipe now installs an original black/crimson Plymouth script theme. A spacecraft orbits the moon while three restrained lights indicate activity. There is no progress percentage, required full orbit, artificial boot wait or video decoder.

**Included in the [regular release](https://github.com/th3d3ck3r/Moonlight-OS/releases/tag/v0.1-experimental.20261002). Build 36995905431 passed installed-image inspection and strict OVMF validation. The previous repair download predates the theme. The user confirmed the boot animation working on the Mac. The newer experimental image retains it and needs a separate physical handoff test.**

## How it is installed

The Kickstart embeds the two PNGs and native script/theme descriptor directly, with no network fetch of mutable artwork. It installs Fedora's Plymouth script and label plugins plus DejaVu Sans, saves the previous theme, selects `crimson-apollo` and runs dracut for the exact pinned kernel after the Cirrus DKMS installation. `rhgb` enables graphics; `plymouth.ignore-serial-consoles` allows the splash while keeping the existing serial console and boot marker.

Fedora's Plymouth quit service remains responsible for normal handoff. Getty follows that service; tty1 also attempts a bounded, best-effort `plymouth quit` before network setup or X11. Both quit units have a five-second failure bound; normal handoff does not wait for animation completion. tty2, the red diagnostic shell, all five frontend choices, Openbox, English labels, media keys, console rows and the Intel/audio fixes remain in place.

The 20 Hz theme caches 72 small padded spacecraft rotations. Layout responds to Plymouth display changes and respects viewport offsets. Password input is represented only by at most 32 stars. Messages cannot replace an active password/question prompt; prompts use a black background and bounded, width-fitting lines. Extremely long messages are limited to eight visible lines; use Escape/serial logs for complete boot details. The theme never logs password contents.

## Focused source checks

```sh
python3 scripts/audit-boot-animation.py --art
python3 scripts/sync-boot-theme.py
bash scripts/validate.sh
python3 scripts/audit-runtime.py
```

On a disposable Fedora 44 environment, run `bash scripts/audit-boot-animation.sh --install-tools`. It uses Fedora's actual script, image, text, math and sprite implementation, checks registered callback names, and tests 320×200, 640×480, 1024×640, 1920×1080 and 2560×1600 plus a display-change event. Its harness supplies display geometry and daemon event registration; **it is not a Plymouth daemon, KMS or successful boot test**. It does not build an image or access a USB drive.

After editing the artwork/theme, run `python3 scripts/sync-boot-theme.py --write`. The audit requires byte-for-byte equality between repository files and their embedded Kickstart copies. GIF/poster previews are not installed into the initramfs.

## Recovery on the animation-enabled image

Press **Escape** during the splash to inspect boot details. Use the existing diagnostic tty or serial output if needed. At GRUB, edit the selected boot entry and append `plymouth.enable=0` for a one-time text boot; remove `rhgb` as well if graphics are unavailable. This does not modify the stored entry.

To persistently restore the stock theme, run these only from the running EclipseOS USB system, after confirming it is the active root. Do not run them against macOS or an internal disk:

```sh
previous=$(cat /etc/moonlight-plymouth-previous-theme)
sudo plymouth-set-default-theme "$previous"
sudo rm -f /etc/dracut.conf.d/90-moonlight-plymouth.conf
sudo dracut --force --kver 6.19.10-300.fc44.x86_64 /boot/initramfs-6.19.10-300.fc44.x86_64.img
sudo grubby --update-kernel=/boot/vmlinuz-6.19.10-300.fc44.x86_64 --remove-args='rhgb plymouth.ignore-serial-consoles' --args='plymouth.enable=0'
```

These commands rebuild the installed USB kernel's initramfs; they are documented recovery operations, not performed as part of this source change. To re-enable later, select `crimson-apollo`, restore the documented dracut module setting, regenerate that initramfs, then remove `plymouth.enable=0` and add `rhgb plymouth.ignore-serial-consoles` using grubby. Keep the working image available until the new boot is proven.

## Physical validation still required

Installed inspection found the native theme files, plugin, selection and initramfs contents, and strict OVMF passed. Preserve these gates in future builds. Test graphical/text boots, missing/unavailable graphics fallback, real prompt/error output, Escape and tty recovery, reboot/suspend policy, and splash-to-network/X11 handoff without delay. On the Mac, confirm the native panel, no stale animation overlay, both clients, Intel decoding, audio, Wi-Fi and the confirmed brightness/volume/backlight keys. OVMF and a script harness cannot prove those physical behaviors.
