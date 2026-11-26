from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
old = json.loads((root / 'baseline-snapshots.json').read_text())['snapshots']
new = json.loads((root / 'candidate-snapshots.json').read_text())['snapshots']
assert len(old) == 192 and old == new, 'Renderer snapshots differ'
assert all(len(value) == 64 for value in old.values())
orders = []
for suffix in ['results', 'repeat']:
    baseline = json.loads((root / f'baseline-{suffix}.json').read_text())['results']
    candidate = json.loads((root / f'candidate-{suffix}.json').read_text())['results']
    assert [(v['kind'], v['revealed']) for v in baseline] == [(v['kind'], v['revealed']) for v in candidate]
    orders.append({'order': 'baseline-first' if suffix == 'results' else 'candidate-first', 'results': [{'kind': a['kind'], 'revealed': a['revealed'], 'baseline_ns': a['median_ns'], 'candidate_ns': b['median_ns'], 'speedup': a['median_ns'] / b['median_ns']} for a, b in zip(baseline, candidate)]})
result = {'matching_snapshots': len(old), 'orders': orders}
(root / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
