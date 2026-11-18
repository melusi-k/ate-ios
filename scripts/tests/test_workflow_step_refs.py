"""Every steps.<id>. reference in a workflow job must resolve to a step id
defined in the same job. Guards against copying step expressions between jobs
whose step ids differ (packet 9 r1 broke SIM_ID this way)."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = sorted((ROOT / '.github' / 'workflows').glob('*.yml'))


def jobs_of(lines):
    in_jobs = False
    jobs = []
    for i, ln in enumerate(lines):
        if ln.startswith('jobs:'):
            in_jobs = True
            continue
        if in_jobs:
            if ln and not ln.startswith(' ') and not ln.startswith('#'):
                in_jobs = False
            elif re.match(r'^  [A-Za-z0-9_-]+:\s*$', ln):
                jobs.append((ln.strip()[:-1], i))
    return jobs


class WorkflowStepRefTests(unittest.TestCase):
    def test_every_steps_reference_resolves_in_job(self):
        self.assertTrue(WORKFLOWS, 'no workflows found')
        bad = []
        for wf in WORKFLOWS:
            lines = wf.read_text().splitlines(keepends=True)
            jobs = jobs_of(lines)
            self.assertTrue(jobs, f'{wf.name} has no jobs')
            for j, (jname, start) in enumerate(jobs):
                end = jobs[j + 1][1] if j + 1 < len(jobs) else len(lines)
                body = lines[start:end]
                ids = set(re.findall(r'^        id: ([A-Za-z0-9_-]+)\s*$', ''.join(body), re.M))
                for ln in body:
                    for ref in re.findall(r'steps\.([A-Za-z0-9_-]+)\.', ln):
                        if ref not in ids:
                            bad.append(f'{wf.name}:{jname}: unresolved steps.{ref}')
        self.assertEqual(bad, [])


if __name__ == '__main__':
    unittest.main()
