"""Exact imported-source review-state inverse, not a native qualification."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='e117e0252a43f9cd78160437ea36adedc0bb7bb75614e222d42006ed6d7b3b18'
def restore(path,raw):
 payload=Path(__file__).with_name('source_review_state_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload).get(path)
 if c is None:return raw
 binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated source review state delta: '+path
 for f in c['fragments']:
  assert text.count(f['new'])==1
  text=text.replace(f['new'],f['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
