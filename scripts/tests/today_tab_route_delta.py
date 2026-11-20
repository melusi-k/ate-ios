"""Exact Today-tab Route.library inverse; historical frozen hashes unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='70f1531939e732ded88c1db20a4a815240f5dd0f92f3b42311c6fd8577829cd8'
def restore(path,raw):
 if path!='Ate/Models/Models.swift':return raw
 payload=Path(__file__).with_name('today_tab_route_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload)[path];binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated today-tab route delta'
 for f in c['fragments']:
  assert text.count(f['new'])==1,'missing/changed/duplicate today-tab route fragment'
  text=text.replace(f['new'],f['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
