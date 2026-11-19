"""Exact inverse for observational workflow additions; frozen pins stay unchanged."""
ENVELOPE = '          # Observation only. Cleanup preserves the native gate\'s original exit.\n          python3 scripts/capture-ocr-host-timing.py --output ocr-host-timing.jsonl > ocr-host-timing-status.log 2>&1 &\n          ocr_host_pid=$!\n          stop_ocr_host_timing() {\n            native_status=$?\n            trap - EXIT\n            kill "$ocr_host_pid" 2>>ocr-host-timing-status.log || true\n            wait "$ocr_host_pid" 2>>ocr-host-timing-status.log || true\n            exit "$native_status"\n          }\n          trap stop_ocr_host_timing EXIT\n'
ARTIFACTS = '            ocr-host-timing.jsonl\n            ocr-host-timing-status.log\n'

def restore(key, raw):
    if key not in ('source:.github/workflows/compile-check.yml', 'main:.github/workflows/compile-check.yml'):
        return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    for block in (ENVELOPE, ARTIFACTS):
        assert text.count(block) == 1, 'OCR host timing inverse absent, changed or duplicated'
        text = text.replace(block, '', 1)
    return text.encode() if binary else text
