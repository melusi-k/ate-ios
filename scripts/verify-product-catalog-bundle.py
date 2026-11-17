#!/usr/bin/env python3
"""Check the actual built Ate.app, never a source-directory approximation."""
import hashlib
import json
from pathlib import Path
import re
import sys


def verify(settings_text, source_root):
    blocks = re.split(r'Build settings for action .*? and target ', settings_text)
    candidates = [block for block in blocks[1:] if block.splitlines()[0].strip() == 'Ate:']
    if len(candidates) != 1:
        raise ValueError('Expected exactly one Ate app target in build settings')
    values = dict(re.findall(r'^\s+([A-Z_]+) = (.*?)\s*$', candidates[0], re.M))
    app = Path(values['TARGET_BUILD_DIR']) / values['WRAPPER_NAME']
    if not app.is_dir():
        raise ValueError('Built app directory does not exist: ' + str(app))
    receipt = {'app': str(app), 'files': []}
    for name in ['roadmap.json', 'catalog.json']:
        packaged = app / 'ProductUpdates' / name
        source = source_root / 'Ate/Resources/ProductUpdates' / name
        if not packaged.is_file():
            raise ValueError('Required packaged catalog missing: ' + str(packaged))
        if packaged.read_bytes() != source.read_bytes():
            raise ValueError('Packaged catalog differs from exact checkout: ' + name)
        if (app / name).exists():
            raise ValueError('Unexpected flattened duplicate: ' + str(app / name))
        receipt['files'].append({'path': str(packaged), 'sha256': hashlib.sha256(packaged.read_bytes()).hexdigest()})
    return receipt


if __name__ == '__main__':
    try:
        print(json.dumps(verify(Path(sys.argv[1]).read_text(), Path(__file__).resolve().parents[1]), indent=2))
    except (ValueError, KeyError, IndexError, OSError) as error:
        raise SystemExit('Catalog bundle verification failed: ' + str(error))
