#!/usr/bin/env python3
"""Fail closed on every explicitly required xcresult Test Case, not console formatting."""
import json
from pathlib import Path
import sys


def validate(document, expected):
    if not isinstance(document, dict) or not isinstance(document.get('testNodes'), list):
        raise ValueError('Unknown xcresult test tree')
    found = {}

    def walk(nodes):
        for node in nodes:
            if not isinstance(node, dict):
                raise ValueError('Malformed xcresult node')
            if node.get('nodeType') == 'Test Case':
                identity = node.get('nodeIdentifier', '')
                if not isinstance(identity, str):
                    raise ValueError('Malformed test identifier')
                if identity.endswith('()'):
                    identity = identity[:-2]
                if identity in found:
                    raise ValueError('Repeated test case: ' + identity)
                found[identity] = node.get('result')
            children = node.get('children', [])
            if not isinstance(children, list):
                raise ValueError('Malformed children')
            walk(children)

    walk(document['testNodes'])
    if set(found) != set(expected):
        raise ValueError('Test set mismatch: missing=' + str(sorted(set(expected) - set(found)))
                         + ' unexpected=' + str(sorted(set(found) - set(expected))))
    bad = {key: value for key, value in found.items() if value != 'Passed'}
    if bad:
        raise ValueError('Non-passing tests: ' + str(bad))
    return sorted(found)


if __name__ == '__main__':
    results = json.loads(Path(sys.argv[1]).read_text())
    expected = Path(sys.argv[2]).read_text().splitlines()
    if not expected or len(expected) != len(set(expected)):
        raise SystemExit('Empty or repeated required identifiers')
    for identity in validate(results, expected):
        print('VERIFIED PASS ' + identity)
