from pathlib import Path
import gzip
import hashlib
import json
lab = Path(__file__).resolve().parent
root = lab.parents[2]
original = gzip.decompress((lab / 'Reference/ContainableController.swift.gz').read_bytes()).decode()
old = (lab / 'Reference/original.txt').read_text().rstrip()
new = (lab / 'Reference/candidate.txt').read_text().rstrip()
assert original.count(old) == 1
current = (root / 'packages/TGUIKit/Sources/ContainableController.swift').read_text()
assert current == original.replace(old, new)
(lab / 'generation.json').write_text(json.dumps({'production_sha256': hashlib.sha256(current.encode()).hexdigest()}, indent=2) + '\n')
