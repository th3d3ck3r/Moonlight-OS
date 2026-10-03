# Separate Mac and generic development tracks

Created October 2, 2026 from source baseline `16d0545d900d0aee37184d267f96ebae6133e4a4`, plus this documentation-only checkpoint. Both branches initially have identical runtime/build source. Existing release downloads and tags are unchanged; the currently published experimental image was built from `ebce257c6429f5b363ba0ec6a17815e524d87f29`. Subsequent source changes make future builds output `.img.xz` directly.

| Branch | Scope |
| --- | --- |
| `main` | Current release baseline and shared fixes. Do not merge unvalidated experimental trimming into it. |
| `mac-minimal` | Future MacBookPro14,1 minimization, prioritizing Vibemis, installed size, unnecessary packages and background work. Begin implementation after the user confirms the current candidate works on the Mac. |
| `generic-hardware` | Preserve today's broader package/driver baseline as the starting point for a later generic x86-64 UEFI edition. |

The split itself removes no packages or drivers and starts no build. Trimming one branch cannot alter files in the other branch. Keep essential Mac hardware, streaming, theme, settings and recovery behavior when minimizing; confirm that apparently generic drivers/firmware are unused by the Mac and its peripherals before removal.

## Generic status

`generic-hardware` still contains the current Mac-specific configuration, including Intel/Apple/Cirrus hardware checks and boot/input/audio policies. It is not yet claimed to boot or accelerate streaming on most PCs. Generalization needs its own hardware detection, driver/firmware choices, conditional Mac fixes, target-appropriate image inspection and physical tests. It must not inherit Mac-only package removals through an indiscriminate merge.

## Shared fixes and validation

Make track-specific changes on the corresponding branch. Port shared Vibemis/theme, Bluetooth, security and build fixes with reviewed cherry-picks or focused patches; avoid wholesale merging either hardware track into the other. Record each candidate's actual source commit, audit/build run, artifact and hardware results separately.

The existing push triggers target `main`. For either development branch, use **Actions → Audit EclipseOS → Run workflow**, selecting that branch. After the appropriate source audits pass and a build is authorized, use **Actions → Build EclipseOS image → Run workflow**, selecting that same branch. Manual builds install from scratch. Branch creation does not automatically start an image build.

Before any future generic build, adapt Mac-only audit/inspection expectations to that target while preserving strict UEFI boot validation. Before publishing either new candidate, update the controlled publication workflow to its specific source, successful run IDs, artifact and separate release notes; the current publisher remains pinned to the existing v0.2 image. Do not relabel the current Mac image as generic.
