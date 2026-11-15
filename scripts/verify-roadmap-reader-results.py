#!/usr/bin/env python3
"""Exactly one named, nonzero roadmap UI pass and one completed invocation."""
import pathlib
import re
import sys

EXPECTED = {'testSettingsRoadmapEmptyCatalogAndUnavailableVotingAtNormalText'}

def verify(text):
    lines = [line.strip() for line in text.splitlines()]
    success = {'** TEST SUCCEEDED **', '** TEST EXECUTE SUCCEEDED **'}
    if sum(line in success for line in lines) != 1 or any(
            line in {'** TEST FAILED **', '** TEST EXECUTE FAILED **', 'Testing failed:'} for line in lines):
        raise ValueError('Expected exactly one successful invocation and no failure marker')
    rows = re.findall(r"Test Case '-\[\S*InsightsPresentationUITests (\w+)\]' (passed|failed) \(([0-9.]+) seconds\)", text)
    if (len(rows) != len(EXPECTED) or {name for name, _, _ in rows} != EXPECTED or
            any(status != 'passed' or float(seconds) <= 0 for _, status, seconds in rows)):
        raise ValueError(f'Expected exact one named nonzero roadmap reader pass, found {rows!r}')
    # Reject other class failures too, never accept a mixed failed log.
    if re.search(r"Test Case '.+' failed \(", text):
        raise ValueError('Failed test record present')
    return len(rows)

if __name__ == '__main__':
    try:
        count = verify(pathlib.Path(sys.argv[1]).read_text())
    except ValueError as error:
        raise SystemExit(str(error))
    print(f'Verified {count} named nonzero roadmap reader UI passes')
