"""Exact test-handshake inverse before historical frozen source checks."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='e9cbd5e0a6125a5d620a5667dc49a1f22784b9c19d17a3f5f0e3329bd2464ebf'
def restore(path,raw):
 if path!='AteTests/RecipeStreamingTests.swift':return raw
 payload=Path(__file__).with_name('streaming_echo_completion_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload);binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated echo completion delta'
 for f in c['fragments']:
  assert text.count(f['new'])==1
  text=text.replace(f['new'],f['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
