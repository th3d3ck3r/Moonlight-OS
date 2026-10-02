# 🌑🚀 Crimson Apollo — self-contained boot-animation integration prompt

**Status:** original animation assets and preview created; Plymouth theme is an **inactive prototype**, not runtime-validated or enabled. No new image build is authorized by this prompt.

## Future execution contract

When explicitly asked to execute this file, integrate the black/crimson Apollo-inspired boot animation into the existing **th3d3ck3r/Moonlight-OS** repository, preserve working features, validate with focused tests, and commit/push source changes. Do **not** dispatch an image build or modify `.github/BUILD_ONCE`. A later explicit build request is required. Do not cancel an unrelated repair build already running.

Read `BUILD_STATUS.md`, `SOURCES.lock`, `config/moonlight-os.ks`, `scripts/build-image.sh`, `scripts/inspect-image.sh`, `scripts/test-ovmf.sh` and `docs/TEST_PLAN.md`. Use `CODEX_BUILD_PROMPT.md` only for preserved invariants, not as authorization to execute its build sequence. Keep the terminal-interface, Liquid Glass GUI and host-overlay plans independent.

Suggested invocation:

> Read CODEX_BOOT_ANIMATION_PROMPT.md in this repository and execute its instructions. Work directly in my existing GitHub repository, preserve the confirmed hardware fixes, use my remaining usage efficiently, quadruple-check the changes, and commit and push them. Do not start a new image build.

## Created assets and visual behavior

Assets live in `assets/boot/crimson-apollo/`. `scripts/render-boot-animation.py` reproducibly draws the original artwork and GIF using Pillow; it does not download mission imagery or third-party theme assets.

- Mostly black starfield, restrained red lunar rim, dark crimson moon/craters.
- Apollo-inspired command/service module follows a circular lunar orbit with tangent orientation.
- Small lunar-module motif, clean Moonlight-OS wordmark and crimson highlights.
- Smooth, infinitely looping **72-frame / 7.2-second** GIF preview with subtle loading lights.
- `background.png` and `apollo.png` support a lightweight Plymouth script theme; `lander.png` is the original separate motif, also baked into the background. `poster.png` is a still preview.
- Small sprites and cached rotations; no full-screen video decoder or compositor. Fit the composition to each detected screen with black margins, without stretching or changing the panel's mode.

[Animated preview](assets/boot/crimson-apollo/preview.gif) · [Still preview](assets/boot/crimson-apollo/poster.png)

The GIF is an art preview, **not a recording of a successful boot**. The prototype theme's script/daemon behavior still needs testing on the selected Fedora Plymouth version. The existing image does not install or activate this theme.

## Integration steps

1. **Audit current boot first.** The current Kickstart has `quiet`, early i915 and serial diagnostics, but no explicit activation of this custom Plymouth theme. Discover the exact Fedora packages, initramfs/module requirements and theme commands from the installed Fedora version; do not copy Ubuntu commands blindly.
2. **Validate the prototype before activation.** Parse/load the script with real Plymouth, verify callback names and image APIs against its installed version, check rotation direction, timing, display offsets, small/large/Retina output, image/font availability in initramfs, and bounded memory/CPU. The example-based refresh cadence is not a measured Fedora timing guarantee. The native theme need not match GIF frame timing exactly, but motion must be smooth and bounded.
3. **Complete recovery and prompt handling.** Test normal, message/error, question and masked-password callbacks, including long text and small screens. Messages must not be clipped, overlap the wordmark or disappear incorrectly. Preserve Escape-to-details and safe text fallback. Mask secrets and never log them. Do not hide boot failure output to keep the animation attractive.
4. **Integrate narrowly.** Add only proven required Plymouth packages/theme files, select the theme and include it in the exact pinned kernel's initramfs. Changes should be isolated, reversible and documented. Keep source/kernel pins, Cirrus driver fixes, full Intel media driver, dynamic GPU checks, Openbox, English client labels, mixer helpers, console geometry and the confirmed media-key service unchanged.
5. **Hand off correctly.** Quit/release Plymouth before the appliance's X11/client session takes the display. Do not create a competing graphical session or grab input from the recovery tty. The animation must never add an artificial delay, wait for a full orbit, fabricate a progress percentage or change boot-marker success criteria. A slow or failed boot must remain diagnosable.
6. **Provide recovery.** Document how to disable the theme and restore the previous initramfs/theme configuration. Keep tty2, red diagnostic shell, serial logs, safe USB root growth and disabled SSH intact. Never touch the internal Mac SSD. Do not add firmware or change GRUB/kernel flags unnecessarily.
7. **Deliver source only.** Run focused theme/package/script audits and existing relevant static checks. Commit/push source and accurate documentation, without launching a new image build. Report what is visually checked, daemon-tested and still untested on the Mac.

## Four checks and later build boundary

1. **Artwork:** decode all PNGs/GIF frames, confirm actual motion and seamless loop, verify no wordmark clipping/spacecraft overlap at orbital extremes, stable palette, responsive composition and small asset sizes.
2. **Theme runtime:** validate with the installed Plymouth parser/daemon, check every asset reference, callback, resize/multi-output behavior, prompt/error rendering and bounded refresh work. Retain text fallback on missing graphics/assets.
3. **Boot integration:** verify initramfs contents and selected kernel, package/theme installation, service ordering and X11 handoff. Preserve serial output and `MOONLIGHT_OS_BOOT_OK`, all hardware policies and recovery entry points. A broken animation must not block boot.
4. **Regression/delivery:** review source/pin diffs, existing static/runtime checks and build scripts. Document activation/rollback and physical checks. **Do not start an image/OVMF build under this prompt.** Once a future build is separately authorized, require installed-image inspection plus the unchanged strict OVMF gate and a real Mac boot/splash/X11-handoff test before calling the animation boot-validated.

Use the smallest relevant audit first, inspect exact failures and avoid rerunning client/audio builds for artwork edits. Preserve the image-size limit. Stop at a source change ready for a separately authorized build; do not silently activate an untested theme on the user's USB.

## API references used for the prototype

The prototype was compared with Plymouth's upstream script example and image/math library source, mirrored at:

- https://github.com/freedesktop-unofficial-mirror/plymouth/blob/master/themes/script/script.script
- https://github.com/freedesktop-unofficial-mirror/plymouth/blob/master/src/plugins/splash/script/script-lib-image.script
- https://github.com/freedesktop-unofficial-mirror/plymouth/blob/master/src/plugins/splash/script/script-lib-math.c

Recheck against the actual Fedora version during integration; these references are not runtime-validation evidence.
