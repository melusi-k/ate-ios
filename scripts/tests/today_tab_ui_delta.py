"""Exact Today-tab UI route inverse; historical frozen hashes unchanged."""
from pathlib import Path
import hashlib,json
from journal_delete_current_query_delta import restore as restore_current_query
FIXTURE_SHA='dca8c1251630f5049cf28bc111a6ca465634619945f89ab48583e49ec4fde85e'
def restore(key,raw):
 from cookplan_cancel_journey_delta import restore as restore_cancel_journey
 raw=restore_cancel_journey(key,raw)
 raw=restore_current_query(key,raw)
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
