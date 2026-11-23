"""Pin the UI-only Journal selection and its explicit full-unit coverage delta."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = 'e22f7f71f6363a91fe25c81dfbe4e4a51b67b99249b045a6d26e1149f032d6a4'

def contract():
    data = Path(__file__).with_name('journal_ui_host_handoff_inverse.json').read_bytes()
    assert hashlib.sha256(data).hexdigest() == FIXTURE_SHA
    return json.loads(data)

def restore(path, source):
    c = contract()['files'][path]
    digest = hashlib.sha256(source.encode()).hexdigest()
    if digest == c['parent_sha256']:
        return source
    assert digest == c['current_sha256']
    for fragment in reversed(c['fragments']):
        assert source.count(fragment['new']) == 1
        source = source.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(source.encode()).hexdigest() == c['parent_sha256']
    return source
