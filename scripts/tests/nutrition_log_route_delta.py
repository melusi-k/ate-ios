"""Exact one-journey route-selection inverse. Historical hashes stay frozen."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '25a817d7cca78f2d6ce578948eda91b7d0c6bbaf4f191b02b5f53eca4dece130'

def restore(key, raw):
    if key.split(':', 1)[-1] != 'AteUITests/NutritionDiaryUITests.swift':
        return raw
    payload = Path(__file__).with_name('nutrition_log_route_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    contract = json.loads(payload)
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha']:
        return raw
    assert hashlib.sha256(text.encode()).hexdigest() == contract['current_sha'], 'unrelated Nutrition route delta'
    assert text.count(contract['new']) == 1, 'missing or duplicate Nutrition route fragment'
    text = text.replace(contract['new'], contract['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha']
    return text.encode() if binary else text
