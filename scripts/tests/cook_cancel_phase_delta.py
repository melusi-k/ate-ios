import hashlib,json
from pathlib import Path
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='67f797c6aa7e55ed757f7b4b46c3599c65a8d47b42f43f8982200377e55a5d4f'

def restore(path,text):
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST
    spec=json.loads(payload)[path]
    assert hashlib.sha256(text.encode()).hexdigest()==spec['patched']
    for fragment in reversed(spec['fragments']):
        assert text.count(fragment['new'])==1
        text=text.replace(fragment['new'],fragment['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==spec['base']
    return text
