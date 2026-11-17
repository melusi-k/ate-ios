"""Exact reviewed opposite-parent inverse deltas; no git or network at runtime."""
import hashlib,json
from pathlib import Path
_FIXTURE=Path(__file__).with_name('approved_merge_539_inverses.json')
_FIXTURE_SHA256='2c43203deb8d312f0ff24e46db405dd4f96ba06cd75f81885cacf298dd375aee'
def normalize_539_parent(key, raw):
    from window_hit_failure_delta import restore as restore_window_hit
    raw=restore_window_hit(key,raw)
    payload=_FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==_FIXTURE_SHA256, 'approved inverse fixture changed'
    contract=json.loads(payload)['contracts'][key]
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    cursor=0
    for item in contract['inverse_fragments']:
        old,new=item['merged_fragment'],item['parent_fragment']
        assert text.count(old)==1, 'approved inverse fragment absent, changed or duplicated: '+key
        start=text.index(old)
        assert start>=cursor, 'approved inverse placement/order changed: '+key
        text=text[:start]+new+text[start+len(old):]
        cursor=start+len(new)
    return text.encode() if binary else text


def approved_original_file(path, raw):
    from cleanup_phase_delta import restore as restore_cleanup
    raw=restore_cleanup("source:"+path,raw)
    from keychain_status_delta import is_added as status_added
    if status_added(path,raw):return False
    from journal_personal_reset_delta import is_added
    if is_added(path, raw): return False
    payload=_FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==_FIXTURE_SHA256
    additions=json.loads(payload)['approved_added_files']
    if path in additions:
        assert hashlib.sha256(raw).hexdigest()==additions[path], 'approved added file changed: '+path
        return False
    assert 'source:'+path in json.loads(payload)['contracts'], 'unreviewed added file: '+path
    return True


def normalize(key, raw):
    from native_sheet_source_delta import restore as restore_native_sheet_source
    raw=restore_native_sheet_source(key,raw)
    from keychain_status_delta import restore as restore_status
    raw=restore_status(key,raw)
    from journal_personal_reset_delta import restore
    from journal_snapshot_mirror_delta import restore as restore_snapshot_mirror
    from journal_reset_test_seams_delta import restore as restore_seams
    from account_539_tools_reveal_delta import restore as restore_tools_reveal
    return normalize_539_parent(key, restore(key, restore_snapshot_mirror(key, restore_seams(key, restore_tools_reveal(key, raw)))))
