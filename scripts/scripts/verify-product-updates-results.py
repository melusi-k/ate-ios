"""Require every selected named release-notes acceptance test, never a zero-test green."""
from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1]
log=Path(sys.argv[1]).read_text()
expected=[]
for folder,filename in [('AteTests','ProductUpdatesTests.swift'),('AteTests','ProductUpdatesLaunchTests.swift'),('AteUITests','ProductUpdatesLaunchUITests.swift')]:
    source=(root/folder/filename).read_text()
    suite=filename.removesuffix('.swift')
    for match in re.finditer(r'(?:final class|extension) (\w+)[^{]*\{|func (test\w+)\(',source):
        if match.group(1): suite=match.group(1)
        else: expected.append((suite,match.group(2)))
expected.append(('InsightsPresentationUITests','testSettingsReleaseNotesAndReplayableTourAtNormalText'))
missing=[f'{suite}.{name}' for suite,name in expected if not re.search(r"Test Case '-\[Ate(?:UI)?Tests\."+re.escape(suite)+' '+re.escape(name)+r"\]' passed",log)]
if missing: raise SystemExit('Missing named passes: '+', '.join(missing))
print(f'All {len(expected)} release-notes named checks passed')
