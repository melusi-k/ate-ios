"""Exact two-command output-stream inverse. Native selections/budgets unchanged."""
from pathlib import Path
import json,hashlib
FIXTURE_SHA='1c6eaa94607d21bb1a0bf0b17169b67643b77425f8faf30c82d0299400a32e21'
def restore(key,raw):
 _marker_probe = raw.decode() if isinstance(raw,bytes) else raw
 if 'openLibraryCollection' in _marker_probe or 'today.recipes' in _marker_probe:
  from today_tab_ui_delta import restore as restore_today_tab_ui
  raw = restore_today_tab_ui(key,raw)
 if key.split(':',1)[-1]!='.github/workflows/compile-check.yml':return raw
 payload=Path(__file__).with_name('ui_progress_stream_inverse.json').read_bytes()
 assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
 c=json.loads(payload);binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
 if '| python3 -u scripts/stream-ui-test-progress.py' not in text:return raw
 for f in c['fragments']:
  assert text.count(f['new'])==1,'missing/changed/duplicate progress stream fragment'
  text=text.replace(f['new'],f['old'],1)
 return text.encode() if binary else text
