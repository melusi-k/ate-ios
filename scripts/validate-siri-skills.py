#!/usr/bin/env python3
"""Validate the constrained Apple Siri app-skill bundle format."""

from __future__ import annotations

import re
import sys
from pathlib import Path

BUNDLE = Path(__file__).resolve().parents[1] / "Skills.skillsbundle"
SKILLS_ROOT = BUNDLE / "Skills"
NAME_PATTERN = re.compile(r"^[a-z0-9-]{1,64}$")


def parse_skill(path: Path) -> tuple[str, str, str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise ValueError(f"{path}: missing YAML front matter")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise ValueError(f"{path}: unterminated YAML front matter")

    frontmatter = text[4:end]
    values: dict[str, str] = {}
    for line in frontmatter.splitlines():
        if not line.strip():
            continue
        if ":" not in line:
            raise ValueError(f"{path}: invalid front matter line: {line!r}")
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key not in {"name", "description"}:
            raise ValueError(f"{path}: unsupported front matter key {key!r}")
        if key in values:
            raise ValueError(f"{path}: duplicate front matter key {key!r}")
        if not value:
            raise ValueError(f"{path}: {key} must not be empty")
        values[key] = value

    if set(values) != {"name", "description"}:
        raise ValueError(f"{path}: front matter must contain only name and description")
    name = values["name"]
    description = values["description"]
    if not NAME_PATTERN.fullmatch(name):
        raise ValueError(f"{path}: name must be 1-64 lowercase letters, digits, or hyphens")
    if "\n" in description or len(description) > 1024:
        raise ValueError(f"{path}: description must be one line and at most 1,024 characters")

    body = text[end + len("\n---\n"):].lstrip("\n")
    if len(body) > 10_000:
        raise ValueError(f"{path}: Markdown body exceeds 10,000 characters")
    return name, description, body


def validate_bundle(bundle: Path = BUNDLE) -> list[str]:
    root = bundle / "Skills"
    if not root.is_dir():
        raise ValueError(f"{bundle}: missing Skills/ directory")

    skill_dirs = sorted(path for path in root.iterdir() if path.is_dir())
    if not skill_dirs:
        raise ValueError(f"{root}: expected at least one skill directory")

    errors: list[str] = []
    for skill_dir in skill_dirs:
        skill_file = skill_dir / "SKILL.md"
        if not skill_file.is_file():
            errors.append(f"{skill_dir}: missing SKILL.md")
            continue
        unexpected = [p.name for p in skill_dir.iterdir() if p.name != "SKILL.md"]
        if unexpected:
            errors.append(f"{skill_dir}: unsupported extra files: {', '.join(sorted(unexpected))}")
        try:
            name, _, _ = parse_skill(skill_file)
            if name != skill_dir.name:
                errors.append(f"{skill_file}: name {name!r} must match directory {skill_dir.name!r}")
        except ValueError as exc:
            errors.append(str(exc))

    if errors:
        raise ValueError("\n".join(errors))
    return [str(path.relative_to(bundle)) for path in sorted(root.glob("*/SKILL.md"))]


if __name__ == "__main__":
    try:
        skills = validate_bundle()
    except ValueError as error:
        print(f"Siri app skill validation failed:\n{error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"Validated {len(skills)} Siri app skill(s):")
    for skill in skills:
        print(f"- {skill}")
