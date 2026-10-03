> This checkpoint has been completed and superseded by [Crimson Glass implementation](CRIMSON_GLASS.md), [four-pass verification](CRIMSON_GLASS_VERIFICATION.md) and [verified automated image build](https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37132195854) from `6f1ce48caa3085cae4b625e7c4ac580f4a6fec48`. Actual previews and downloads are in the README. Physical acceptance remains pending. The original paused state below is archived context, not current production status.

# Crimson Glass — paused WIP handoff, October 3, 2026

Production main remains e01d9b5629de32246a5e33e496428021bce5ce48. No new image was started. This branch is a checkpoint, NOT a verified build.

User selected Obsidian Cockpit concept (three-column dashboard) but explicitly named the actual UI **Crimson Glass**. Include small live graphs in the streaming overlay. Theme the WHOLE Eclipse frontend: host/app views, settings/control center, Wi-Fi/Bluetooth pickers, confirmations, menus/QuickMenu and overlays; correct spacing, rounded corners, text, all 16 accents, reduced motion/high contrast. Add a saved selectable background with dimming and reset. Repository remains Moonlight-OS; product EclipseOS/frontend Eclipse. Keep current build for side-by-side comparison.

## Recover source
Apply patches/crimson-glass-wip.patch to CLEAN pinned Vibemis commit c3032fc8ee56188a91c1f5a3a8aeae6cf36fb6de from SOURCES.lock. This is the COMPLETE patch (461960 bytes), including all previously shipped Eclipse features. Do NOT apply it on top of patches/vibemis-crimson.patch. git apply --check passed against clean pinned tree. Production patch and embedded installer payload remain old; synchronize only after review.

## WIP implemented
- Shared CrimsonGlassPanel/Backdrop/Rail/HostPanel/LocalPanel/Sparkline and themed BackgroundPicker.
- PcView/AppView responsive margins and sidebars around existing real model/delegates; pairing/launch/context menu and controller paths preserved. Model objects now parent to their owning grid explicitly.
- Shared token palette, glass surfaces on dialogs, menus, controls/settings/QuickMenu, scaled host-card text and reduced-motion status pulse.
- LocalHardware consumer leases keep sampling while any visible monitor needs it.
- Profile-owned background validation (local only, <=32 MiB, dimensions bounded), resized <=2560 image saved atomically into app data; settings picker/reset/dimming (30..90%), high contrast stronger scrim.
- Native stream/local overlay graph histories: bounded 60 samples, NaN gaps, measured rendering FPS / network latency parsing, local CPU/RAM, graph mutex; preserve detailed stats toggle and SDL/TTF fallback paths.
- Focused test additions: graph source/missing/window, wallpaper source deletion/persistence/rejection, consumer lifecycle, actual production views with fixture models.

## Verification state
First full local Qt suite: 19 passed before final production-view smoke additions. Latest qmlPaletteAndPanels (actual PcView/AppView and panel tests): PASS, zero QML-engine warnings, 3 harness entries passed (init/test/cleanup).
Tests exercised 1920x1080, 1280x720, 900x640 and 100/110/125% text.
Final whole suite after latest additions NOT yet run. Full native Fedora frontend/decoder compile/startup, source CI and image inspection/OVMF NOT yet run for WIP. Do not claim physical hardware or functional streaming passed.
Previous known TLS fixture emits QNetworkReply internal warning; latest QML fixture has none.

## Continue in this order
1. Inspect latest actual host/app screenshots and navigation: narrow/scaled text, focus rail/grids, ghost Add-PC geometry, resize margins, background picker and theme coverage. Fix issues.
2. Review graph semantics, concurrency/history lifecycle, failure fallbacks and sampling consumers; cover genuinely missing behavior.
3. Run final full Qt suite, Python BlueZ/System Controls/connection fixtures, static checks. Preserve all prior fixes.
4. Promote verified complete WIP to patches/vibemis-crimson.patch; scripts/sync-frontend-payloads.py then --check. Do not build stale embedded payload.
5. Commit reviewed source; require all 7 exact-source audits, including native Fedora full client/decoder build and GUI startup. Only then trigger .github/BUILD_ONCE.
6. Verify installed payload and strict OVMF MOONLIGHT_OS_BOOT_OK, then uploaded ZIP/checksum/names/size/expiry.
7. Refresh README preserving formatting, clearly label both current System Controls build and NEW Crimson Glass build. Keep all older fallbacks. Update known issues and verification docs, provide actual screenshots (fixture metrics labelled), then download links.

## Comparison build (preserve)
https://github.com/th3d3ck3r/Moonlight-OS/actions/runs/37105853178/artifacts/11268692925
Exact image source 4755e352876e48b73521ec28dec9015e514bded2, all 7 audits, installed-image inspection and strict OVMF passed. ZIP 3.89 GiB; raw 12.24 GiB; 16 GB drive minimum; expiry Oct 17. Contains eclipseos-mbp14-1.img.xz and checksum. Physical Bluetooth controller power-off/reconnect, sensors and sustained streaming remain pending.

## Original workspace
/workspace/scratch/eaef7118fe26
OS repo EclipseOS-rename, customized source vibemis-eclipseos, clean pin vibemis-clean-check.
Qt deps qt-root/usr; focused build eclipse-ui-tests.
Latest test log eclipse-ui-tests/crimson-glass-visual.log.
Actual screenshots crimson-glass-previews/crimson-glass-PcView-*.png and crimson-glass-AppView-*.png.
Selected revised concept generated_images/exec-312292e2-c276-49a8-8575-308902fb47d4.png.
Complete snapshot also /workspace/scratch/eaef7118fe26/CrimsonGlass-WIP.patch.
If original scratch absent, use this remote checkpoint. Read available AGENTS/skills and inspect files first. No proactive subagents. User authorized remaining implementation/checks/build/docs, paused only to switch chat.
