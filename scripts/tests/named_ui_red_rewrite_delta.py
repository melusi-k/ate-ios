"""Reverse only the named-red method rewrites before historical source pins."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='4d334ecba48eca33f96f177209676fc32132b7a045fb4580caa3a7b6230b35a7'
def restore(key,raw):
 path=key.split(':',1)[-1]
 payload=Path(__file__).with_name('named_ui_red_rewrite_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload).get(path)
 if c is None:return raw
 binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 # Older historical transforms can call this again. No rewrite means no delta.
 marker='NamedRedReceipt(self,'
 if marker not in text:return raw
 for f in c['fragments']:
  assert text.count(f['new'])==1,'missing/changed/duplicate named-red method: '+path
  text=text.replace(f['new'],f['old'],1)
 return text.encode() if binary else text
