#!/usr/bin/env python3
"""Snapshot published build-tag change subjects into the offline release catalog.

Run deliberately when adding history, not during every build. Existing authored
(non-build) catalog entries are preserved. No network or model-written claims.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Ate/Resources/ProductUpdates/catalog.json'
PROVENANCE = ROOT / 'docs/release-history-sources.json'
SNAPSHOT = ROOT / 'docs/published-release-snapshot.json'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def readable_subject(subject):
    # A filename, implementation packet or qualification result is not a feature claim.
    if re.search(r'\.(swift|py|yml|yaml|json|md|sql|sh|txt|png|jpg)\b|[/\\]', subject, re.I):
        return None
    if re.search(r'\b(ci|test[s]?|fixture[s]?|helper[s]?|workflow[s]?|reviewer|reviewed|packet|checkout|assertion[s]?|simulator|compile|qualification|source|union|fold|cherry.pick|branch|commit|telemetry|gate[s]?|capture[s]?|lane[s]?|evidence|pilot)\b', subject, re.I):
        return None
    cleaned = re.sub(r'^(?:feat|fix|perf|refactor|chore|docs|test|ci)(?:\([^)]*\))?[!:]+\s*', '', subject, flags=re.I)
    if re.search(r'prompt\(\)|predicate|selector|quarantine|design review|proposal|re.admission|unverified|seam|backend|supabase', cleaned, re.I):
        return None
    cleaned = re.sub(r'^#\d+\s*[: -]*\s*', '', cleaned).strip()
    if not cleaned or len(cleaned) > 150:
        return None
    # Keep only subjects with a recognizable app-facing topic. Others remain in
    # provenance, rather than exposing engineering shorthand as release copy.
    if not re.search(r'\b(recipe[s]?|cook\w*|journal|shopping|timer[s]?|spotlight|sync|sign.in|account|onboarding|import|export|search|nutrition|meal[s]?|photo[s]?|screenshot[s]?|ingredient[s]?|step[s]?|library|settings|draft[s]?|widget[s]?|watch|health|backup|restore|prompt[s]?|notification[s]?)\b', cleaned, re.I):
        return None
    return cleaned[:1].upper() + cleaned[1:]


def build_entry(published, previous):
    tag = published["tag"]
    sha = published["source_commit"]
    build = int(re.fullmatch(r'build-(\d+)(?:-.+)?', tag)[1])
    # Same previous-tag..build range as gen-build-notes.py. For the oldest
    # available tag, retain its final20 non-merge subjects rather than all history.
    args = ['log', '--no-merges', '--format=%H%x09%s']
    args += [f'{previous}..{sha}'] if previous else ['-20', sha]
    records = [dict(zip(('commit', 'subject'), row.split('\t', 1))) for row in git(*args).splitlines() if '\t' in row]
    spec = git('show', f'{sha}:project.yml')
    match = re.search(r'MARKETING_VERSION:\s*["\']?([\d.]+)', spec)
    if not match:
        raise ValueError(f'Cannot establish version for {tag}')
    return render_entry(published, previous, records, match[1])


def render_entry(published, previous, records, source_version):
    """Pure offline rendering, suitable for shallow-checkout snapshot validation."""
    tag = published['tag']
    sha = published['source_commit']
    build = int(re.fullmatch(r'build-(\d+)(?:-.+)?', tag)[1])
    chosen = []
    for record in records:
        text = readable_subject(record['subject'])
        if text and text not in [entry['text'] for entry in chosen]:
            chosen.append({'text': text, 'commit': record['commit'], 'subject': record['subject']})
    # GitHub release name records the distributed marketing version; project.yml
    # has a generic version that the archive workflow replaces.
    match = re.search(r'(?<![\d.])(\d+\.\d+\.\d+)(?![\d.])', published['name'])
    if not match:
        match = re.match(r'([\d.]+)', source_version)
    if not match:
        raise ValueError(f'Cannot establish version for {tag}')
    # The published release's explicit main-feature heading is better product
    # copy than source-fold subjects. Retain it verbatim when available.
    notes = published['notes'].replace('\r\n', '\n').replace('\r', '\n')
    focus = re.search(r'^### Main feature focus[ \t]*\n+(.*?)(?=^### |\Z)', notes, re.M | re.S)
    focus_paragraphs = [p.strip() for p in re.split(r'\n\s*\n', focus[1].strip())] if focus else []
    summary = focus_paragraphs[0] if focus_paragraphs else (chosen[0]['text'] if chosen else 'Behind the scenes')
    changes = [{'kind': 'improved', 'text': entry['text']} for entry in chosen]
    # Retain the published feature-focus paragraph, including acceptance caveats.
    for paragraph in reversed(focus_paragraphs[1:]):
        text = re.sub(r'^Focus:\s*', '', paragraph)
        changes.insert(0, {'kind': 'improved', 'text': text})
    if not changes:
        changes = [{'kind': 'improved', 'text': 'The saved build notes contain no readable feature summary.'}]
    release = {'id': tag, 'title': f'Build {build}', 'version': match[1],
               'buildNumber': build, 'minimumBuild': build, 'channel': 'all',
               'summary': summary, 'changes': changes, 'slides': []}
    provenance = {'tag': tag, 'commit': sha, 'previous_commit': previous, 'release_url': published['url'],
                  'source_version': source_version, 'selected': chosen, 'recorded_changes': records}
    return release, provenance


def generate():
    published = json.loads(SNAPSHOT.read_text())['releases']
    published.sort(key=lambda row: (int(re.search(r'\d+', row['tag'])[0]), row['tag']))
    entries, sources = [], []
    for index, release in enumerate(published):
        entry, source = build_entry(release, published[index - 1]['source_commit'] if index else None)
        entries.append(entry)
        sources.append(source)
    current = json.loads(CATALOG.read_text())
    authored = [entry for entry in current['releases'] if 'buildNumber' not in entry]
    current['releases'] = authored + list(reversed(entries))
    return current, {'format': 1, 'method': 'Previous published build release to this build release; non-merge Git subjects. Oldest tag: final20 subjects.',
                     'builds': list(reversed(sources))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify checked-in snapshot against the available tags')
    args = parser.parse_args()
    catalog, sources = generate()
    outputs = [(CATALOG, catalog), (PROVENANCE, sources)]
    if args.check:
        for path, expected in outputs:
            if json.loads(path.read_text()) != expected:
                raise SystemExit(f'Stale release history: {path.relative_to(ROOT)}')
    else:
        for path, value in outputs:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    print(f'{len(sources["builds"])} build-tag entries verified; {len(catalog["releases"])} total catalog entries')
