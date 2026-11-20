"""Exact follow-up copy correction. Original refusal inverse hashes unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='5ed80cebf3d59b8534eec5d160288000eb5443391fb1040222db7bd6d368099d'
def restore(path,raw):
 if path=='Ate/Views/AddRecipeSheet.swift' and 'showDiscovery' in (raw.decode() if isinstance(raw,bytes) else raw):
  from suggest_new_recipe_entry_delta import restore as restore_entry
  raw = restore_entry(path,raw)
 if path!='Ate/Views/AddRecipeSheet.swift':return raw
 payload=Path(__file__).with_name('source_refusal_route_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload);binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated refusal route wording delta'
 assert text.count(c['new'])==1
 text=text.replace(c['new'],c['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
