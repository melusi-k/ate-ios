#!/usr/bin/env python3
"""Read-only native/Python inventory and conservative, non-authorizing CI dry run."""
import argparse
import ast
import fnmatch
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOTS = ('AteTests', 'AteUITests', 'AteClipTests', 'AteModelReadinessTests')
PROTECTED = ('scripts/ci-mapping.py', 'ci/', '.github/')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def inventory(repo):
    """Source discovery, not a claim of XCTest runtime discovery or execution."""
    entries, errors = [], []
    for target in ROOTS:
        if not (repo / target).is_dir():
            errors.append('missing test target source root: ' + target)
        for path in sorted((repo / target).rglob('*.swift')):
            source = path.read_text()
            # Mask comments and quoted literals before matching braces/declarations.
            masked = re.sub(r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\])*"',
                            lambda m: '\n' * m[0].count('\n') + ' ' * (len(m[0]) - m[0].count('\n')),
                            source, flags=re.S)
            if re.search(r'@Test\b', masked):
                errors.append(str(path.relative_to(repo)) + ': Swift Testing requires a new inventory adapter')
            spans = []
            for match in re.finditer(r'\b(?:class|extension)\s+(\w+)[^{]*\{', masked):
                depth, end = 1, match.end()
                while depth and end < len(masked):
                    depth += (masked[end] == '{') - (masked[end] == '}')
                    end += 1
                if depth:
                    errors.append(str(path.relative_to(repo)) + ': unbalanced declaration')
                spans.append((match.end(), end, match[1]))
            for match in re.finditer(r'\bfunc\s+(test\w+)\s*\(', masked):
                parents = [s for s in spans if s[0] <= match.start() < s[1]]
                if not parents:
                    errors.append(str(path.relative_to(repo)) + ': test without owning class')
                    continue
                owner = max(parents)[2]
                entries.append({'selector': target + '/' + owner + '/' + match[1],
                                'path': str(path.relative_to(repo)), 'kind': 'native'})
    for path in sorted((repo / 'scripts/tests').rglob('test_*.py')):
        tree = ast.parse(path.read_text())
        for cls in (n for n in tree.body if isinstance(n, ast.ClassDef)):
            for method in cls.body:
                if isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)) and method.name.startswith('test_'):
                    entries.append({'selector': path.stem + '.' + cls.name + '.' + method.name,
                                    'path': str(path.relative_to(repo)), 'kind': 'python'})
    ids = [e['selector'] for e in entries]
    if len(ids) != len(set(ids)):
        errors.append('duplicate source test identities')
    return {'schema': 1, 'basis': 'source declarations only; NOT execution evidence',
            'entries': sorted(entries, key=lambda e: e['selector']), 'errors': errors}


def changes(repo, base, head):
    for rev in (base, head):
        if not re.fullmatch(r'[0-9a-f]{40}', rev):
            raise ValueError('base/head must be full immutable commit SHAs')
        git(repo, 'cat-file', '-e', rev + '^{commit}')
    merge_base = git(repo, 'merge-base', base, head).decode().strip()
    fields = git(repo, 'diff', '--name-status', '-z', '-M', merge_base, head).decode().split('\0')
    result, i = [], 0
    while i < len(fields) and fields[i]:
        status, path = fields[i:i+2]
        i += 2
        row = {'status': status, 'path': path}
        if status.startswith(('R', 'C')):
            row['previous_path'] = path
            row['path'] = fields[i]
            i += 1
        result.append(row)
    return merge_base, result


def resolve(manifest, current_inventory, diff, base, head, trusted):
    errors, areas, unknown = [], set(), []
    entries = current_inventory['entries']
    available = {e['selector'] for e in entries}
    paths = [p for row in diff for p in [row['path'], row.get('previous_path')] if p]
    if not diff:
        errors.append('empty diff requires review')
    if not trusted:
        errors.append('bootstrap: base-trusted resolver/manifest unavailable')
    if current_inventory.get('errors'):
        errors.extend(current_inventory['errors'])
    if manifest.get('schema') != 1:
        errors.append('unsupported manifest schema')
    for area, record in manifest.get('areas', {}).items():
        if not record.get('selectors'):
            errors.append('empty area mapping: ' + area)
        if len(record.get('selectors', [])) != len(set(record.get('selectors', []))):
            errors.append('duplicate selector in area: ' + area)
        for selector in record.get('selectors', []):
            if selector not in available:
                errors.append('unknown/deleted selector: ' + selector)
    for path in paths:
        if path.startswith(PROTECTED):
            errors.append('mapping/security/infra path requires conservative review: ' + path)
        matches = [name for name, record in manifest.get('areas', {}).items()
                   if any(fnmatch.fnmatchcase(path, pat) for pat in record['paths'])]
        if not matches:
            unknown.append(path)
        areas.update(matches)
    if unknown:
        errors.append('unknown paths require conservative review')
    # No not-selected Journal/compile/unit claim in this dry run.
    fallback = bool(errors) or 'shared' in areas
    selected = {e['selector'] for e in entries if e['kind'] == 'native'} if fallback else {
        s for area in areas for s in manifest['areas'][area]['selectors']}
    if not selected:
        errors.append('empty resolved selection')
        fallback = True
        selected = {e['selector'] for e in entries if e['kind'] == 'native'}
    return {'schema': 1, 'mode': 'DRY_RUN_ONLY', 'authorizes_narrowing': False,
            'qualification': 'NOT RUN; existing gates unchanged', 'base_sha': base, 'head_sha': head,
            'mapping_gate': 'review_required' if errors or fallback else 'proposed_only',
            'areas': sorted(areas), 'unknown_paths': sorted(set(unknown)), 'reasons': sorted(set(errors)),
            'fallback': 'complete discovered native inventory' if fallback else None,
            'selectors': sorted(selected), 'changed_files': diff,
            'inventory_caveat': current_inventory['basis']}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=Path('.'))
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--base')
    parser.add_argument('--head')
    parser.add_argument('--bootstrap', action='store_true')
    parser.add_argument('--write-inventory', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    inv = inventory(args.repo)
    if args.write_inventory:
        args.write_inventory.write_text(json.dumps(inv, indent=2) + '\n')
        return int(bool(inv['errors']))
    if not all((args.manifest, args.base, args.head, args.output)):
        parser.error('plan requires manifest, base, head and output')
    raw = args.manifest.read_bytes()
    manifest = json.loads(raw)
    ancestor, diff = changes(args.repo, args.base, args.head)
    # Trust is demonstrated by byte-equality with base blobs, never by a caller flag.
    trusted = False
    if not args.bootstrap:
        try:
            trusted = (git(args.repo, 'show', args.base + ':scripts/ci-mapping.py') == Path(__file__).read_bytes()
                       and git(args.repo, 'show', args.base + ':ci/test-area-map.json') == raw)
        except subprocess.CalledProcessError:
            pass
    plan = resolve(manifest, inv, diff, args.base, args.head, trusted)
    plan.update({'diff_ancestor_sha': ancestor, 'manifest_sha256': digest(raw),
                 'resolver_sha256': digest(Path(__file__).read_bytes()),
                 'inventory_sha256': digest(json.dumps(inv, sort_keys=True).encode())})
    args.output.write_text(json.dumps(plan, indent=2) + '\n')
    print('Dry-run plan written. No tests selected for execution, no gates changed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
