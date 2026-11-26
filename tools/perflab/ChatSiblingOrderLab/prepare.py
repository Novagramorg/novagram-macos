from pathlib import Path
import gzip
import hashlib
import json
lab = Path(__file__).resolve().parent
root = lab.parents[2]
original = gzip.decompress((lab / 'Reference/ChatLayerScene.swift.gz').read_bytes()).decode()
metadata = json.loads((lab / 'Reference/provenance.json').read_text())
assert hashlib.sha256(original.encode()).hexdigest() == metadata['original_sha256']
old = (lab / 'Reference/original.txt').read_text().rstrip()
new = (lab / 'Reference/candidate.txt').read_text().rstrip()
assert original.count(old) == 1
current = (root / 'packages/ChatUI/Sources/ChatUI/ChatLayerScene.swift').read_text()
assert current == original.replace(old, new)
(lab / 'generation.json').write_text(json.dumps({'production_sha256': hashlib.sha256(current.encode()).hexdigest()}, indent=2) + '\n')
