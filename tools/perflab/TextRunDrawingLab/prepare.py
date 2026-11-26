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
    for name in ['TextView.swift', 'TextNode.swift']:
        (output / 'TGUIKit/Sources' / name).write_bytes(subprocess.check_output(['git', 'show', f'8557150e7:packages/TGUIKit/Sources/{name}'], cwd=root))
    (output / 'TGUIKit/Sources/TextRunDrawing.swift').unlink()
destination = output / 'TextRunDrawingLab/Sources'
if destination.exists():
    shutil.rmtree(destination)
shutil.copytree(lab / 'Sources', destination)
(output / 'TextRunDrawingLab/Package.swift').write_text((lab / 'Package.swift').read_text().replace('../../../packages/TGUIKit', '../TGUIKit'))
paths = list((output / 'TGUIKit/Sources').glob('Text*.swift')) + list((destination / 'TextRunDrawingLab').glob('*.swift'))
(output / 'provenance.json').write_text(json.dumps({'variant': variant, 'baseline': '8557150e7', 'sha256': {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}, indent=2) + '\n')
