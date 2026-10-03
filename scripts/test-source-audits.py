#!/usr/bin/env python3
import runpy
from pathlib import Path

gate = runpy.run_path(str(Path(__file__).with_name("wait-source-audits.py")))
run = {"head_sha": "exact-source", "path": ".github/workflows/audit.yml", "status": "completed", "conclusion": "success"}
jobs = [{"name": name, "status": "completed", "conclusion": "success"} for name in gate["EXPECTED"]]
assert gate["verified"](run, jobs, "exact-source")
assert not gate["verified"](run, jobs, "different-source")
assert not gate["verified"](run, jobs[:-1], "exact-source")
assert not gate["verified"](run, jobs + [jobs[0]], "exact-source")
for conclusion in ("failure", "cancelled", "skipped", None):
    assert not gate["verified"](run, [dict(job, conclusion=conclusion) if job["name"] == "fedora" else job for job in jobs], "exact-source")
assert not gate["verified"](dict(run, status="in_progress"), jobs, "exact-source")
assert not gate["verified"](dict(run, path="different.yml"), jobs, "exact-source")
print("Exact-source build gate accepts seven successes and rejects stale, missing, failed and pending audits.")
