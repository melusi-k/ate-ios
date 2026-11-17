"""Exact additive runtime-query layer over the unchanged original workflow pin."""
import hashlib
ORIGINAL_SHA256 = '0bd051599259cdb676b361f920e646dea7d08a0cca9730cec6d3cdcca833a83f'
RUNTIME_QUERY_SHA256 = 'b80f711118fb31fe62058d0f270cf5a481eea3ccfa2198259228ee177ddae533'
FRAGMENTS = [('import datetime, json, os, runpy, subprocess, time', 'import datetime, json, os, subprocess, time'), ('              selector = runpy.run_path("scripts/select-ios-simulator.py")\n              if selector["runtime_version"](runtime) is None or device["name"] != selector["EXPECTED_DEVICE"]:', '              if runtime.rsplit(".", 1)[-1] != "iOS-27-0" or device["name"] != "iPhone 18 Pro":')]
def restore(source):
    digest = hashlib.sha256(source.encode()).hexdigest()
    if digest == ORIGINAL_SHA256: return source
    assert digest == RUNTIME_QUERY_SHA256, 'Unreviewed Journal readiness workflow delta'
    for new, old in FRAGMENTS:
        assert source.count(new) == 1
        source = source.replace(new, old, 1)
    assert hashlib.sha256(source.encode()).hexdigest() == ORIGINAL_SHA256
    return source
