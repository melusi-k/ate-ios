#!/usr/bin/env python3
"""Require every named native unit pass from xcresult, never console fragments."""
import json
from pathlib import Path
import sys


def validate(document, expected):
    if not expected or len(expected) != len(set(expected)):
        raise ValueError('Empty or repeated required identifiers')
    if not isinstance(document, dict) or not isinstance(document.get('testNodes'), list):
        raise ValueError('Unknown xcresult test tree')
    found = {}

    def walk(nodes):
        for node in nodes:
            if not isinstance(node, dict):
                raise ValueError('Malformed xcresult node')
            if node.get('nodeType') == 'Test Case':
                identity = node.get('nodeIdentifier')
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
    missing = set(expected) - set(found)
    if missing:
        raise ValueError('Missing required tests: ' + str(sorted(missing)))
    bad = {key: found[key] for key in expected if found[key] != 'Passed'}
    if bad:
        raise ValueError('Non-passing required tests: ' + str(bad))
    return sorted(expected)


if __name__ == '__main__':
    results = json.loads(Path(sys.argv[1]).read_text())
    for identity in validate(results, Path(sys.argv[2]).read_text().splitlines()):
        print('VERIFIED PASS ' + identity)
