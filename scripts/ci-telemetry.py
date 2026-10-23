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
from typing import Any


def parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def seconds(start: str | None, end: str | None) -> float | None:
    a, b = parse_time(start), parse_time(end)
    if not a or not b:
        return None
    return round(max(0.0, (b - a).total_seconds()), 2)


def api_json(url: str, token: str) -> dict[str, Any]:
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


def collect_jobs(run_data: dict[str, Any], jobs: list[dict[str, Any]]) -> dict[str, Any]:
    """Normalize job/step metadata without exposing logs or arbitrary API fields."""
    starts = [job.get("started_at") for job in jobs if job.get("started_at")]
    first_start = min(starts) if starts else None
    result: dict[str, Any] = {
        "workflow_created_at": run_data.get("created_at"),
        "run_status": run_data.get("status"),
        "run_conclusion": run_data.get("conclusion"),
        # This is deliberately named for what it measures. GitHub's created_at
        # is not a queue timestamp and may include dispatch/scheduling overhead.
        "workflow_creation_to_first_job_start_seconds": seconds(run_data.get("created_at"), first_start),
        "jobs": [],
    }
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
        result["jobs"].append({
            "name": job.get("name"),
            "status": job.get("status"),
            "conclusion": job.get("conclusion"),
            "started_at": job.get("started_at"),
            "completed_at": job.get("completed_at"),
            "duration_seconds": seconds(job.get("started_at"), job.get("completed_at")),
            "creation_to_start_seconds": seconds(run_data.get("created_at"), job.get("started_at")),
            "steps": step_rows,
        })
    return result


def build_report(env: dict[str, str], run_data: dict[str, Any] | None = None,
                 jobs: list[dict[str, Any]] | None = None,
                 collection_status: str = "metadata_only") -> dict[str, Any]:
    report: dict[str, Any] = {
        "schema_version": 1,
        "repository": env.get("GITHUB_REPOSITORY") or None,
        "workflow": env.get("GITHUB_WORKFLOW"),
        "run_id": int(env["GITHUB_RUN_ID"]) if env.get("GITHUB_RUN_ID", "").isdigit() else None,
        "run_attempt": int(env.get("GITHUB_RUN_ATTEMPT", "1")) if env.get("GITHUB_RUN_ATTEMPT", "1").isdigit() else 1,
        "commit_sha": env.get("GITHUB_SHA"),
        "ref": env.get("GITHUB_REF"),
        "event_name": env.get("GITHUB_EVENT_NAME"),
        "runner_os": env.get("RUNNER_OS"),
        "runner_arch": env.get("RUNNER_ARCH"),
        "jobs": [],
        "collection_status": collection_status,
    }
    if run_data is not None:
        normalized = collect_jobs(run_data, jobs or [])
        report.update({key: value for key, value in normalized.items() if key != "jobs"})
        report["jobs"] = normalized["jobs"]
    return report


def main() -> int:
    env = dict(os.environ)
    repository = env.get("GITHUB_REPOSITORY", "")
    run_id = env.get("GITHUB_RUN_ID", "")
    token = env.get("GITHUB_TOKEN", "")
    output = Path(env.get("RUNNER_TEMP", ".")) / "ate-ci-telemetry.json"
    report = build_report(env)

    if repository and run_id and token:
        base = f"https://api.github.com/repos/{repository}/actions/runs/{run_id}"
        try:
            run_data = api_json(base, token)
            response = api_json(base + "/jobs?per_page=100", token)
            report = build_report(env, run_data, response.get("jobs", []))
        except (OSError, ValueError, TypeError, urllib.error.URLError, TimeoutError) as error:
            # Best effort only. Avoid emitting exception text that could include
            # transport details or credentials; always attempt to write the report.
            report["collection_status"] = "partial_or_unavailable"
            print(f"CI telemetry metadata collection unavailable ({type(error).__name__}).", file=sys.stderr)
    else:
        report["collection_status"] = "missing_github_metadata_or_token"

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"CI telemetry report written: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
