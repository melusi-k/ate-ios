"""Exact Add terminal-deadline inverse, before unchanged ownership pins."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA = '0589e86a6a3723b19fcfeebea8b6461c4206ea55cd52fdff29e1c06b68aad628'
def restore(path, text):
    from verified_paste_import_delta import restore as restore_paste
    if path != 'Ate/Views/AddRecipeSheet.swift': text = restore_paste(path, text)
    payload=Path(__file__).with_name('add_generation_deadline_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA, 'deadline inverse changed'
    contract=json.loads(payload).get(path)
    if contract is None: return text
    for fragment in contract['fragments']:
        assert text.count(fragment['new'])==1, 'deadline fragment absent, changed or duplicated'
        text=text.replace(fragment['new'],fragment['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==contract['parent_sha'], 'parent changed outside deadline delta'
    return text
