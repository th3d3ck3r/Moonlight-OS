# Updater source verification — October 3, 2026

This evidence applies to the prepared `wip/eclipseos-updater` source, not an installed image or signed production release. Existing Crimson Glass/comparison artifacts are unchanged.

| Pass | Check | Result |
| --- | --- | --- |
| 1: scope and integration | Fixed target registry, exact base/kernel receipt, existing source pins/patch unchanged, launcher/installer/recovery ordering review | Kernel, firmware, modules, partitions, credentials and arbitrary package paths excluded; all five launch paths preserved |
| 2: updater behavior | `python3 scripts/test-updater.py` | **35 tests pass** using temporary roots and ephemeral keys |
| 3: existing regression checks | `bash scripts/validate.sh` and `python3 scripts/audit-runtime.py` | Pass: embedded Bash, payload equality, boot-animation audit, 6 system-control + 17 control-center + 6 BlueZ tests, exact-source gate fixtures, updater tests, GPU and media-key fixtures |
| 4: final source review | `git diff --check`, standalone/embedded payload synchronization, recovery unit ordering and manual source-only workflow assertions | Pass; no image trigger, build dispatch, native compile or live installation |

Fault tests cover interrupted multi-file writes, interruption between mutation and state save, interruption after durable confirmation, service restart failure, repeated restart failure followed by offline boot recovery, backup corruption, signature/hash mismatch, path/link rejection, local changes, syntax errors, stale sequences, wrong base, unsupported frontend architecture, exclusive locking, active-client refusal and explicit rollback after confirmation. The real package-creation script is exercised with disposable test inputs; no production release package is created.

Before use, enrollment and a real release still need an owner-controlled signing key, native frontend/Qt/decode checks where relevant, a disposable installed-image activation/reboot trial and physical Mac Wi-Fi/Bluetooth/controller recovery acceptance. The UI is terminal/tty2 in this first version. See [the update guide](UPDATES.md).
