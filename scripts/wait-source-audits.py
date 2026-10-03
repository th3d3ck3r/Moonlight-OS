#!/usr/bin/env python3
"""Require all seven audit jobs on the exact image source before installation."""
import json
import os
import time
import urllib.request

EXPECTED = {"root-growth", "image-tools", "static", "fedora", "audio", "boot-animation", "vibemis-crimson"}


def verified(run, jobs, sha):
    if run.get("head_sha") != sha or run.get("path") != ".github/workflows/audit.yml":
        return False
    return (run.get("status") == "completed" and run.get("conclusion") == "success"
            and len(jobs) == len(EXPECTED) and {job["name"] for job in jobs} == EXPECTED
            and all(job.get("status") == "completed" and job.get("conclusion") == "success" for job in jobs))


def main():
    repository, sha = os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"]
    token = os.environ["GH_AUDIT_TOKEN"]

    def fetch(path):
        request = urllib.request.Request("https://api.github.com/repos/" + repository + path,
            headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    deadline = time.monotonic() + 1200
    while time.monotonic() < deadline:
        runs = fetch("/actions/workflows/audit.yml/runs?head_sha=" + sha + "&per_page=20")["workflow_runs"]
        if runs:
            run = max(runs, key=lambda item: item["id"])
            if run["status"] == "completed":
                jobs = fetch("/actions/runs/" + str(run["id"]) + "/jobs?per_page=100")["jobs"]
                if not verified(run, jobs, sha):
                    raise SystemExit("Exact-source audit failed or omitted a required job; image installation blocked.")
                print("All seven exact-source audits passed:", run["html_url"], sha, flush=True)
                return
        print("Waiting for all seven exact-source audits before image installation.", flush=True)
        time.sleep(15)
    raise SystemExit("Exact-source audit wait timed out; image installation blocked.")


if __name__ == "__main__":
    main()
