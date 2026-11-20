"""Exact one-line wording inverse, refusal behavior untouched."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='7ef5725cf8b96b95be1c215af34fe01d67b8f340e12f38dcf16ff289ca605923'
def restore(path,raw):
 from source_refusal_route_delta import restore as restore_route
 raw = restore_route(path,raw)
 if path!='Ate/Views/AddRecipeSheet.swift':return raw
 payload=Path(__file__).with_name('source_refusal_wording_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload);binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated refusal wording delta'
 assert text.count(c['new'])==1
 text=text.replace(c['new'],c['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
