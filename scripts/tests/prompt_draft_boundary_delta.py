"""Exact accepted Prompt publication delta, before unchanged historical pins."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA = '05aebc07ba400c66e6d78f3537bad0faf1d0226df2d731bf91d40c8d17e432ca'
def restore(path, text):
    payload=Path(__file__).with_name('prompt_draft_boundary_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA, 'prompt boundary inverse changed'
    contract=json.loads(payload).get(path)
    if contract is None: return text
    for fragment in contract['fragments']:
        assert text.count(fragment['new'])==1, 'prompt boundary fragment absent, changed or duplicated'
        text=text.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest()==contract['parent_sha'], 'parent source changed outside prompt delta'
    return text
