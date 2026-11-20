"""Exact Today-tab UI route inverse; historical frozen hashes unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='a59d291428139f6844fefd91cbd9fefcac306901d779c34b273dec3e90518877'
def restore(key,raw):
 path=key.split(':',1)[-1]
 payload=Path(__file__).with_name('today_tab_ui_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload).get(path)
 if c is None:return raw
 binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated today-tab UI delta: '+path
 for f in c['fragments']:
  if f.get('all'):
   assert text.count(f['new'])==f['count'],'missing/changed/duplicate today-tab UI fragment: '+path
   text=text.replace(f['new'],f['old'])
  else:
   assert text.count(f['new'])==1,'missing/changed/duplicate today-tab UI fragment: '+path
   text=text.replace(f['new'],f['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
