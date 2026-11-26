from pathlib import Path
import hashlib
import json
import re
import shutil
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists()
metadata = json.loads((lab / 'Reference/provenance.json').read_text())
reference = lab / 'Reference/InvisibleInkDustView.swift.txt'
compiled_reference = lab / 'Sources/OriginalInkDust/OriginalInvisibleInkDustView.swift'
assert hashlib.sha256(reference.read_bytes()).hexdigest() == metadata['captured_class_sha256']
assert hashlib.sha256(compiled_reference.read_bytes()).hexdigest() == metadata['compiled_reference_sha256']
source = root / metadata['source']
assert hashlib.sha256(source.read_bytes()).hexdigest() == metadata['candidate_full_source_sha256']
shutil.copytree(lab, output, ignore=shutil.ignore_patterns('.build', 'results', '__pycache__'))
kit = root / 'packages/TGUIKit'
copy = output / 'TGUIKit'
hashes = {}
for folder in ['Sources', 'Tests']:
    for path in (kit / folder).rglob('*'):
        if path.is_file():
            relative = path.relative_to(kit)
            destination = copy / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            data = path.read_bytes()
            destination.write_bytes(data)
            hashes[str(path.relative_to(root))] = hashlib.sha256(data).hexdigest()
for path in lab.rglob('*'):
    if path.is_file() and '.build' not in path.parts and 'results' not in path.parts:
        hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
for relative, expected in hashes.items():
    assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == expected
manifest = (kit / 'Package.swift').read_text()
hashes[str((kit / 'Package.swift').relative_to(root))] = hashlib.sha256(manifest.encode()).hexdigest()
manifest = re.sub(r'(path: ")([^"]+)', lambda m: m[1] + str((kit / m[2]).resolve()) if m[2].startswith('..') else m[0], manifest)
(copy / 'Package.swift').write_text(manifest)
path = output / 'Package.swift'
path.write_text(path.read_text().replace('../../../packages/TGUIKit', str(copy)))
(output / 'source-manifest.json').write_text(json.dumps(hashes, indent=2, sort_keys=True) + '\n')
print(output)
