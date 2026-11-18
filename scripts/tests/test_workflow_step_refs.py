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


def run_blocks_of(lines):
    """Yields (name, block_text) for each step with a run key, in order."""
    steps = []
    cur = None
    for ln in lines:
        if ln.startswith('      - '):
            if cur is not None:
                steps.append(cur)
            cur = [ln]
        elif cur is not None:
            cur.append(ln)
    if cur is not None:
        steps.append(cur)
    for st in steps:
        text = ''.join(st)
        if re.search(r'^        run: ', text, re.M):
            yield st[0].strip(), text


def mkdir_args_of(text):
    return re.findall(r'mkdir -p ([^\s&|]+)', text)


def covers(mkdirs, target):
    """mkdir -p M creates M and its parents: target is created iff some mkdir arg
    equals target or sits under it."""
    return any(m == target or m.startswith(target + '/') for m in mkdirs)


class WorkflowRuntimeRefTests(unittest.TestCase):
    def test_sim_id_assigned_or_exported_before_use(self):
        # $SIM_ID must be assigned in the same run block or exported to GITHUB_ENV
        # by an earlier run step in the same job (packet 9 r2 / packet 11 r2 bugs).
        bad = []
        for wf in WORKFLOWS:
            lines = wf.read_text().splitlines(keepends=True)
            jobs = jobs_of(lines)
            for j, (jname, start) in enumerate(jobs):
                end = jobs[j + 1][1] if j + 1 < len(jobs) else len(lines)
                body = lines[start:end]
                env_exported = False
                for name, text in run_blocks_of(body):
                    if ('$SIM_ID' in text or '${SIM_ID' in text):
                        assigns = bool(re.search(r'^\s*SIM_ID=', text, re.M)) or bool(re.search(r'^          SIM_ID: ', text, re.M))
                        if not assigns and not env_exported:
                            bad.append(f'{wf.name}:{jname}:{name[:50]}: $SIM_ID used without assignment')
                    if re.search(r'SIM_ID=.*>> "?\$GITHUB_ENV"?', text):
                        env_exported = True
        self.assertEqual(bad, [])

    def test_result_and_export_parent_dirs_created_in_job(self):
        # Folded-journeys job only: every -resultBundlePath / --output-path parent
        # directory must be created by an mkdir -p in the same job, no later than the
        # using step (packet 11 r1 bug: $RUNNER_TEMP/ate-test-results was never created
        # in the folded job). Other jobs are covered by their own live native evidence
        # and stay out of this check's scope.
        bad = []
        for wf in WORKFLOWS:
            if wf.name != 'dogfood-qualification.yml':
                continue
            lines = wf.read_text().splitlines(keepends=True)
            jobs = jobs_of(lines)
            for j, (jname, start) in enumerate(jobs):
                if jname != 'folded-journeys':
                    continue
                end = jobs[j + 1][1] if j + 1 < len(jobs) else len(lines)
                body = lines[start:end]
                made = []
                for name, text in run_blocks_of(body):
                    targets = re.findall(r'-resultBundlePath "?([^\s\\"]+)', text)
                    targets += re.findall(r'--output-path "?([^\s"&]+)', text)
                    targets += re.findall(r'--output "?([^\s"&]+)', text)
                    for t in targets:
                        t = t.replace("${{ runner.temp }}", "$RUNNER_TEMP")
                        parent = t.rsplit('/', 1)[0] if '/' in t else ''
                        if not parent or parent in ('.', '$RUNNER_TEMP'):
                            continue
                        if not covers(made + mkdir_args_of(text), parent):
                            bad.append(f'{wf.name}:{jname}:{name[:50]}: parent not created: {parent}')
                    made += mkdir_args_of(text)
        self.assertEqual(bad, [])


if __name__ == '__main__':
    unittest.main()
