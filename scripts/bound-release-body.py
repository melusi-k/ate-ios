#!/usr/bin/env python3
"""Bound GitHub release notes without changing the full run-summary notes."""
from pathlib import Path
import sys

# GitHub permits 125000 characters. A 100000-byte UTF-8 ceiling leaves room
# below that limit regardless of Unicode, and keeps the install/SHA footer.
MAX_BYTES = 100000
NOTICE = ("\n\n[Middle of source history omitted to fit GitHub's release-body limit. "
          "Full notes are in the linked CI run summary.]\n\n").encode("utf-8")


def bounded_body(text):
    data = text.encode("utf-8")
    if len(data) <= MAX_BYTES:
        return text
    head_size = 60000
    tail_size = MAX_BYTES - head_size - len(NOTICE)
    head = data[:head_size].decode("utf-8", errors="ignore")
    tail = data[-tail_size:].decode("utf-8", errors="ignore")
    return head + NOTICE.decode("utf-8") + tail


if __name__ == "__main__":
    source, destination = map(Path, sys.argv[1:])
    destination.write_text(bounded_body(source.read_text(encoding="utf-8")), encoding="utf-8")
