"""Exact Suggest-a-new-recipe entry inverse; historical frozen hashes unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='fa8e4da7b79d7be20676b500077cbbabc92f93096d5abf5ab59d013e303ae0f0'
def restore(path,raw):
 if path!='Ate/Views/AddRecipeSheet.swift':return raw
 payload=Path(__file__).with_name('suggest_new_recipe_entry_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload)[path];binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated suggest-entry delta'
 for f in c['fragments']:
  assert text.count(f['new'])==1,'missing/changed/duplicate suggest-entry fragment'
  text=text.replace(f['new'],f['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
