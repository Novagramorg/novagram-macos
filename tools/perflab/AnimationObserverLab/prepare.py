from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
variant, output = sys.argv[1:]
assert variant in ('baseline', 'candidate')
output = Path(output)
kit = root / 'packages/TGUIKit'
for name in ['Sources', 'Tests']:
    destination = output / 'TGUIKit' / name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(kit / name, destination)
manifest = (kit / 'Package.swift').read_text()
manifest = re.sub(r'(\.package\(name: "[^"]+", path: ")([^"]+)', lambda m: m[1] + str((kit / m[2]).resolve()), manifest)
(output / 'TGUIKit/Package.swift').write_text(manifest)
if variant == 'baseline':
    for name in ['AnimatableContentObserver.swift', 'TableRowView.swift']:
        (output / 'TGUIKit/Sources' / name).write_bytes(subprocess.check_output(['git', 'show', f'70b45f289:packages/TGUIKit/Sources/{name}'], cwd=root))
destination = output / 'AnimationObserverLab/Sources'
if destination.exists():
    shutil.rmtree(destination)
shutil.copytree(lab / 'Sources', destination)
(output / 'AnimationObserverLab/Package.swift').write_text((lab / 'Package.swift').read_text().replace('../../../packages/TGUIKit', '../TGUIKit'))
paths = [output / 'TGUIKit/Sources/AnimatableContentObserver.swift', output / 'TGUIKit/Sources/TableRowView.swift'] + list((destination / 'AnimationObserverLab').glob('*.swift'))
(output / 'provenance.json').write_text(json.dumps({'variant': variant, 'baseline': '70b45f289', 'sha256': {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}, indent=2) + '\n')
