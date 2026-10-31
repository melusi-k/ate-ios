#!/usr/bin/env python3
"""Validate stacked-PR metadata and immediate-parent relationship in GitHub Actions."""
import json, os, re, sys, urllib.error, urllib.request

def fail(message):
    print(f"::error::{message}")
    raise SystemExit(1)

def field(body, name):
    match = re.search(rf"^\s*-\s*\*\*{re.escape(name)}:\*\*\s*(.*?)\s*$", body, re.M)
    if not match: fail(f"PR Stack section is missing **{name}:**")
    return match.group(1)

def api_pr(repo, number, token):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/pulls/{number}",
        headers={"Accept":"application/vnd.github+json","Authorization":f"Bearer {token}","X-GitHub-Api-Version":"2022-11-28"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response: return json.load(response)
    except urllib.error.HTTPError as error:
        fail(f"Unable to inspect parent PR #{number}: GitHub API returned HTTP {error.code}")

def main():
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path: fail("GITHUB_EVENT_PATH is required")
    with open(event_path, encoding="utf-8") as source: event = json.load(source)
    pr = event.get("pull_request")
    if not pr:
        print("No pull_request payload; stack validation is not applicable."); return
    body = pr.get("body") or ""
    section = re.search(r"^## Stack\s*$(.*?)(?=^## |\Z)", body, re.M | re.S)
    if not section: fail("PR description must include a ## Stack section")
    stack_id, parent, position = (field(section.group(1), name) for name in ("Stack ID","Parent PR","Position"))
    if stack_id == parent == position == "None":
        print("Standalone PR metadata valid."); return
    if "None" in (stack_id,parent,position): fail("Stack ID, Parent PR, and Position must all be None or all populated")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{2,63}", stack_id): fail("Stack ID must be a lowercase slug (3–64 characters)")
    if not re.fullmatch(r"[1-9][0-9]*", parent): fail("Parent PR must be a positive PR number (digits only)")
    if not re.fullmatch(r"[1-9][0-9]*/[1-9][0-9]*", position): fail("Position must use N/Total notation, for example 2/3")
    current,total = map(int,position.split("/"))
    if current < 2 or total < current: fail("A child PR position must be at least 2 and no greater than Total")
    repo = pr["base"]["repo"]["full_name"]
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token: fail("GITHUB_TOKEN is required to validate the parent PR")
    parent_pr = api_pr(repo,int(parent),token)
    if parent_pr["state"] != "open": fail(f"Parent PR #{parent} is not open; resolve the stack before proceeding")
    if parent_pr["base"]["repo"]["full_name"].lower() != repo.lower(): fail("Cross-repository stacks are not supported")
    parent_section = re.search(r"^## Stack\s*$(.*?)(?=^## |\Z)",parent_pr.get("body") or "",re.M|re.S)
    if not parent_section: fail(f"Parent PR #{parent} has no ## Stack metadata")
    parent_id = field(parent_section.group(1),"Stack ID")
    parent_position = field(parent_section.group(1),"Position")
    if parent_id != stack_id: fail(f"Stack ID mismatch: child uses {stack_id}, parent uses {parent_id}")
    if parent_position == "None": fail("A stacked child cannot depend on a standalone parent")
    parent_index,parent_total = map(int,parent_position.split("/"))
    if parent_index + 1 != current or parent_total != total: fail("Position must increment by one from immediate parent and share its Total")
    if pr["base"]["ref"] != parent_pr["head"]["ref"]:
        fail(f"Stack base mismatch: child targets {pr['base']['ref']}, but parent #{parent} head is {parent_pr['head']['ref']}")
    if parent_pr["head"]["repo"]["full_name"].lower() != repo.lower(): fail("Parent branch must be in the same repository")
    print(f"Stack metadata valid: {stack_id}, PR #{parent} → PR #{pr['number']} ({position}); base={pr['base']['ref']}")

if __name__ == "__main__": main()
