from pathlib import Path
import hashlib
import gzip
import json
import re
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists()
subprocess.run([sys.executable, str(lab / 'prepare.py')], check=True)
shutil.copytree(lab, output, ignore=shutil.ignore_patterns('.build', 'results'))
kit = root / 'packages/TGUIKit'
copy = output / 'TGUIKit'
hashes = {}
for folder in ['Sources', 'Tests']:
    for path in (kit / folder).rglob('*'):
        if path.is_file():
            relative = path.relative_to(kit)
            destination = copy / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
            hashes[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
for relative, expected in hashes.items():
    assert hashlib.sha256((kit / relative).read_bytes()).hexdigest() == expected
    assert hashlib.sha256((copy / relative).read_bytes()).hexdigest() == expected
manifest = (kit / 'Package.swift').read_text()
manifest = re.sub(r'(path: ")([^"]+)', lambda m: m[1] + str((kit / m[2]).resolve()) if m[2].startswith('..') else m[0], manifest)
(copy / 'Package.swift').write_text(manifest)
path = output / 'Package.swift'
path.write_text(path.read_text().replace('../../../packages/TGUIKit', str(copy)))
baseline = output / 'TGUIKitBaseline'
shutil.copytree(copy, baseline)
path = baseline / 'Package.swift'
path.write_text(path.read_text().replace('"TGUIKit"', '"TGUIKitBaseline"').replace('name: "TGUIKitTests"', 'name: "TGUIKitBaselineTests"'))
path = baseline / 'Sources/BlurEdgeView.swift'
original = gzip.decompress((lab / 'Reference/BlurEdgeView.swift.gz').read_bytes())
metadata = json.loads((lab / 'Reference/provenance.json').read_text())
assert hashlib.sha256(original).hexdigest() == metadata['original_sha256']
path.write_bytes(original)
(output / 'snapshot.json').write_text(json.dumps(hashes, indent=2) + '\n')
print(output)

for folder, name in [(copy, 'candidate-inspection.swift.txt'), (baseline, 'baseline-inspection.swift.txt')]:
    path = folder / 'Sources/BlurEdgeView.swift'
    path.write_text(path.read_text() + (lab / name).read_text())
