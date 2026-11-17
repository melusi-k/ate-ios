#!/usr/bin/env python3
"""Exact named selection and evidence gate for the manual Cook matrix."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

CASES = {
    'CookGoldenCaptureUITests/testCookGoldenMediumDetent': ['cook-golden-medium', 'cook-golden-medium-midscroll', 'cook-golden-medium-finalAsk'],
    'CookGoldenCaptureUITests/testCookGoldenLargeDetent': ['cook-golden-large', 'cook-golden-large-midscroll', 'cook-golden-large-finalAsk'],
    'CookGoldenCaptureUITests/testCookGoldenPushedDetail': ['cook-golden-pushed', 'cook-golden-pushed-midscroll', 'cook-golden-pushed-finalAsk', 'cook-golden-pushed-opened-cook'],
    'CookFinishAccessoryUITests/testPushedFinishAboveResumeAccessoryPortrait': ['cook-finish-clear-of-resume-portrait'],
    'CookFinishAccessoryUITests/testPushedFinishAboveResumeAccessoryLandscape': ['cook-finish-clear-of-resume-landscape'],
    'CookSharedStepUITests/testExternalSharedStepChangeWhileCookIsOpenUpdatesCurrentStep': [],
    'CoverageUITests/testBottomBarsDoNotOverlapRecipeDetail': ['detail-bottom-bars'],
}

def configure(path):
    data = plistlib.loads(path.read_bytes())
    found = 0
    def walk(value):
        nonlocal found
        if isinstance(value, dict):
            if value.get('IsUITestBundle') is True:
                value.setdefault('EnvironmentVariables', {})['ATE_COOK_GOLDENS'] = '1'
                found += 1
            for child in value.values(): walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    walk(data)
    if found != 1: raise ValueError('Expected exactly one UI test bundle')
    path.write_bytes(plistlib.dumps(data))

def verify(raw, log, output):
    text = log.read_text()
    manifest = json.loads((raw / 'manifest.json').read_text())
    output.mkdir(parents=True, exist_ok=True)
    receipts = []
    for case, captures in CASES.items():
        cls, method = case.split('/')
        if f"{cls} {method}]' passed" not in text:
            raise ValueError('Missing named test pass: ' + case)
        groups = [g for g in manifest if g.get('testIdentifier', '').rstrip('()') == case]
        if len(groups) != 1: raise ValueError('Missing/repeated test manifest: ' + case)
        for name in captures:
            matches = [a for a in groups[0]['attachments'] if a.get('suggestedHumanReadableName', '').startswith(name + '_') and a.get('exportedFileName', '').endswith('.png')]
            if len(matches) != 1: raise ValueError('Missing/repeated capture: ' + name)
            source = (raw / matches[0]['exportedFileName']).resolve()
            if source.parent != raw.resolve(): raise ValueError('Escaping capture path')
            data = source.read_bytes()
            if not data.startswith(b'\x89PNG\r\n\x1a\n'): raise ValueError('Not PNG: ' + name)
            # Native decode, not just a signature/file-existence check.
            result = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(source)], check=True, capture_output=True, text=True)
            dimensions = [int(line.split(':')[1]) for line in result.stdout.splitlines() if 'pixelWidth:' in line or 'pixelHeight:' in line]
            if len(dimensions) != 2 or min(dimensions) < 300: raise ValueError('Invalid dimensions: ' + name)
            (output / (name + '.png')).write_bytes(data)
            receipts.append(dict(test=case, capture=name, sha256=hashlib.sha256(data).hexdigest(), dimensions=dimensions, timestamp=matches[0].get('timestamp')))
    (output / 'receipts.json').write_text(json.dumps(receipts, indent=2))

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['select', 'configure', 'verify'])
    p.add_argument('--xctestrun', type=Path)
    p.add_argument('--raw', type=Path)
    p.add_argument('--log', type=Path)
    p.add_argument('--output', type=Path)
    args = p.parse_args()
    if args.mode == 'select': print('\n'.join('-only-testing:AteUITests/' + case for case in CASES))
    elif args.mode == 'configure': configure(args.xctestrun)
    else: verify(args.raw, args.log, args.output)
