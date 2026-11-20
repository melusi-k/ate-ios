"""Exact metadata label style inverse before historical whole-file guards."""
from pathlib import Path
import json,hashlib
FIXTURE_SHA='09c03406e5725f08ef76255b82ed64e2aed9fc75563eee2870da7970a7c1b5bf'
def restore(path,raw):
 if path!='Ate/Views/Components.swift':return raw
 payload=Path(__file__).with_name('row_metadata_style_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload);binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
 assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated metadata style delta'
 assert text.count(c['new'])==1
 text=text.replace(c['new'],c['old'],1)
 assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
 return text.encode() if binary else text
