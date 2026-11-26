from pathlib import Path
import gzip
import hashlib
import json
lab = Path(__file__).resolve().parent
root = lab.parents[2]
original = gzip.decompress((lab / 'Reference/ChatLayerScene.swift.gz').read_bytes()).decode()
metadata = json.loads((lab / 'Reference/provenance.json').read_text())
assert hashlib.sha256(original.encode()).hexdigest() == metadata['original_sha256']
expected = original
for old, new in json.loads((lab / 'Reference/changes.json').read_text()):
    assert expected.count(old) == 1
    expected = expected.replace(old, new)
current = (root / 'packages/ChatUI/Sources/ChatUI/ChatLayerScene.swift').read_text()
assert current == expected
(lab / 'generation.json').write_text(json.dumps({'production_sha256': hashlib.sha256(current.encode()).hexdigest()}, indent=2) + '\n')
