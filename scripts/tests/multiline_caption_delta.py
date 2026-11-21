"""Exact additive caption route inverse; historical frozen hashes unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='5921e82c3e8fdf6ccba2004b4f9e22d9be9ae38425cbbb95a7e5788887b44016'
def restore(path,raw):
 if path!='Ate/Services/OnDeviceBackend.swift':return raw
 payload=Path(__file__).with_name('multiline_caption_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload)[path];binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated multiline caption delta'
 assert text.count(c['new'])==1
 text=text.replace(c['new'],'',1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
