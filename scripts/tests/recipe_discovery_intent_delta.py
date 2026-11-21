"""Exact creative-discovery inverse before unchanged source-import/history pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = 'd7010c178b0e83d636776bd66b5ef96002a21283c0e8161801a59a927d2a1744'

def restore(path, text):
    from suggest_review_buttons_delta import restore as restore_buttons
    text = restore_buttons(path,text)
    if path != 'Ate/Services/OnDeviceBackend.swift':
        from verified_paste_import_delta import restore as pre_simplification
        text = pre_simplification(path,text)
    payload = Path(__file__).with_name('recipe_discovery_intent_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA, 'discovery inverse changed'
    contracts = json.loads(payload)
    if path not in contracts:
        return text
    contract = contracts[path]
    for fragment in contract['fragments']:
        assert text.count(fragment['new']) == 1, 'discovery fragment absent, changed or duplicated'
        text = text.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha'], 'discovery parent changed outside delta'
    return text
