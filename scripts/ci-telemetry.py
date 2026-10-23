#!/usr/bin/env python3
"""Write a privacy-minimal GitHub Actions timing report for this workflow run.

Uses only GitHub Actions metadata. It does not collect source contents, secrets,
test logs, or app/user data. Missing timing fields are represented as null.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path


def parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def seconds(start: str | None, end: str | None) -> float | None:
    a, b = parse_time(start), parse_time(end)
    if not a or not b:
        return None
    return round(max(0.0, (b - a).total_seconds()), 2)


def api_json(url: str, token: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ate-ci-telemetry",
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


def main() -> int:
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    token = os.environ.get("GITHUB_TOKEN", "")
    output = Path(os.environ.get("RUNNER_TEMP", ".")) / "ate-ci-telemetry.json"
    run = {
        "schema_version": 1,
        "repository": repository or None,
        "workflow": os.environ.get("GITHUB_WORKFLOW"),
        "run_id": int(run_id) if run_id.isdigit() else None,
        "run_attempt": int(os.environ.get("GITHUB_RUN_ATTEMPT", "1")),
        "commit_sha": os.environ.get("GITHUB_SHA"),
        "ref": os.environ.get("GITHUB_REF"),
        "event_name": os.environ.get("GITHUB_EVENT_NAME"),
        "runner_os": os.environ.get("RUNNER_OS"),
        "runner_arch": os.environ.get("RUNNER_ARCH"),
        "jobs": [],
        "collection_status": "metadata_only",
    }

    if repository and run_id and token:
        base = f"https://api.github.com/repos/{repository}/actions/runs/{run_id}"
        try:
            run_data = api_json(base, token)
            run["created_at"] = run_data.get("created_at")
            run["run_status"] = run_data.get("status")
            run["run_conclusion"] = run_data.get("conclusion")
            run["workflow_queue_seconds_to_first_job"] = None
            response = api_json(base + "/jobs?per_page=100", token)
            jobs = response.get("jobs", [])
            starts = [j.get("started_at") for j in jobs if j.get("started_at")]
            first_start = min(starts) if starts else None
            run["workflow_queue_seconds_to_first_job"] = seconds(run_data.get("created_at"), first_start)
            for job in jobs:
                step_rows = []
                for step in job.get("steps", []):
                    step_rows.append({
                        "name": step.get("name"),
                        "number": step.get("number"),
                        "status": step.get("status"),
                        "conclusion": step.get("conclusion"),
                        "duration_seconds": seconds(step.get("started_at"), step.get("completed_at")),
                    })
                run["jobs"].append({
                    "name": job.get("name"),
                    "status": job.get("status"),
                    "conclusion": job.get("conclusion"),
                    "started_at": job.get("started_at"),
                    "completed_at": job.get("completed_at"),
                    "duration_seconds": seconds(job.get("started_at"), job.get("completed_at")),
                    "queue_seconds_from_run_creation": seconds(run_data.get("created_at"), job.get("started_at")),
                    "steps": step_rows,
                })
        except (OSError, ValueError, urllib.error.URLError, TimeoutError) as error:
            # Keep telemetry non-blocking. Do not emit exception text that could
            # contain transport details or credentials into the artifact.
            run["collection_status"] = "partial_or_unavailable"
            print(f"CI telemetry metadata collection unavailable ({type(error).__name__}).", file=sys.stderr)
    else:
        run["collection_status"] = "missing_github_metadata_or_token"

    output.write_text(json.dumps(run, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"CI telemetry report written: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
