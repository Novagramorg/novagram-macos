from pathlib import Path
import gzip, hashlib, json
lab = Path(__file__).resolve().parent
root = lab.parents[2]
meta = json.loads((lab / 'Reference/provenance.json').read_text())
for name, info in meta.items():
    original = gzip.decompress((lab / 'Reference' / (name + '.gz')).read_bytes())
    assert hashlib.sha256(original).hexdigest() == info['original_sha256']
    candidate = original.decode()
    for before, after in info['replacements']:
        assert candidate.count(before) == 1
        candidate = candidate.replace(before, after)
    assert (root / 'packages/TGUIKit/Sources' / name).read_text() == candidate
