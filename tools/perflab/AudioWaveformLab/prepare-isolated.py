from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()), 'Use an output directory under /tmp'
assert not output.exists(), 'Use a fresh output directory'
shutil.copytree(lab, output, ignore=shutil.ignore_patterns('.build', 'results'))
path = output / 'prepare.py'
source = path.read_text().replace('root = lab.parents[2]', 'root = Path(' + repr(str(root)) + ')')
path.write_text(source.replace('.relative_to(root)', ''))
subprocess.run([sys.executable, str(path)], check=True)
kit = root / 'packages/TGUIKit'
kit_copy = output / 'TGUIKit'
paths = [p for folder in ['Sources', 'Tests'] for p in (kit / folder).rglob('*') if p.is_file()]
paths.append(kit / 'Package.swift')
hashes = {str(p.relative_to(kit)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
for path in paths:
    destination = kit_copy / path.relative_to(kit)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, destination)
for name, expected in hashes.items():
    assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == expected
    assert hashlib.sha256((kit_copy / name).read_bytes()).hexdigest() == expected
manifest = (kit_copy / 'Package.swift').read_text()
manifest = re.sub(r'(path: ")([^"]+)', lambda match: match[1] + str((kit / match[2]).resolve()) if match[2].startswith('..') else match[0], manifest)
(kit_copy / 'Package.swift').write_text(manifest)
path = output / 'Package.swift'
path.write_text(path.read_text().replace('../../../packages/TGUIKit', str(kit_copy)))
(output / 'tguikit-snapshot.json').write_text(json.dumps(hashes, indent=2) + '\n')
print(output)
