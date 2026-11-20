"""Exact Add source-required delta above composed deadline stack."""
from pathlib import Path
import json,hashlib
FIXTURE_SHA = 'd3223fca803706574ba42420a03bbaa920266fa2a731c9f378e02c2f76b056a9'
def restore(path,text):
    from verified_paste_import_delta import restore as restore_paste
    text = restore_paste(path,text)
    payload=Path(__file__).with_name('add_prompt_source_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return text
    for f in c['fragments']:
        assert text.count(f['new'])==1
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
    return text
