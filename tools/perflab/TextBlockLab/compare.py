from pathlib import Path
import json
import sys

directory = Path(sys.argv[1])

def load(name):
    return json.loads((directory / name).read_text())['results']

baseline = load('baseline-snapshots.json')
candidate = load('candidate-snapshots.json')
assert baseline == candidate, 'Rendered masks differ'
assert len(baseline) == 144
assert any(row['image_sha256'] != 'nil' for row in baseline)
timings = []
for suffix in ['', '-repeat']:
    before = load('baseline' + suffix + '.json')
    after = load('candidate' + suffix + '.json')
    assert len(before) == len(after)
    for a, b in zip(before, after):
        for key in ['kind', 'mode', 'scale', 'alignment', 'lines', 'image_sha256', 'width', 'height', 'x', 'y']:
            assert a[key] == b[key], (suffix, key, a, b)
        timings.append({'run': suffix or 'first', 'kind': a['kind'], 'mode': a['mode'], 'baseline_us': a['median_us'], 'candidate_us': b['median_us'], 'speedup': a['median_us'] / b['median_us']})
output = {'identical_rendered_masks': len(baseline), 'timings': timings}
(directory / 'comparison.json').write_text(json.dumps(output, indent=2) + '\n')
print(json.dumps(output, indent=2))
