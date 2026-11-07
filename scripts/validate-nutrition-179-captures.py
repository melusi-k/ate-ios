#!/usr/bin/env python3
"""Require complete, decoded named UI screenshots. Pixel review remains a separate gate."""
import base64
from pathlib import Path
import subprocess
import sys

log = Path(sys.argv[1]).read_text()
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for name in ('nutrition-linked-recipe', 'nutrition-unlinked-recipe',
             'nutrition-corrupt-links', 'nutrition-prefill-failed-draft',
             'nutrition-prefill-reviewed-values'):
    lines = log.splitlines()
    begins = [line for line in lines if line.startswith('SNAPSHOT-BEGIN ' + name + ' ')]
    ends = [line for line in lines if line == 'SNAPSHOT-END ' + name]
    if len(begins) != 1 or len(ends) != 1:
        raise SystemExit('Missing or repeated screenshot: ' + name)
    start, finish = lines.index(begins[0]), lines.index(ends[0])
    if start >= finish:
        raise SystemExit('Unordered screenshot: ' + name)
    prefix = 'SNAPSHOT-CHUNK ' + name + ' '
    chunks = [line[len(prefix):] for line in lines[start + 1:finish] if line.startswith(prefix)]
    encoded = ''.join(chunks)
    if len(encoded) != int(begins[0].rsplit(' ', 1)[1]):
        raise SystemExit('Truncated screenshot: ' + name)
    data = base64.b64decode(encoded, validate=True)
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise SystemExit('Not PNG: ' + name)
    path = out / (name + '.png')
    path.write_bytes(data)
    result = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)],
                            check=True, capture_output=True, text=True)
    dimensions = [int(line.split(':')[1]) for line in result.stdout.splitlines()
                  if 'pixelWidth:' in line or 'pixelHeight:' in line]
    if len(dimensions) != 2 or min(dimensions) < 300:
        raise SystemExit('Undecodable or tiny screenshot: ' + name)
    print('Decoded required capture:', name, dimensions)
