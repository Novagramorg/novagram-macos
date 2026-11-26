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
baseline_text = subprocess.check_output(['git', 'show', '314247f46:packages/TGUIKit/Sources/TextView.swift'], cwd=root).decode()
start = baseline_text.index('    public func generateBlock(for range:')
end = baseline_text.index('    public func generateAutoBlock(', start)
methods = baseline_text[start:end].replace('public func generateBlock(', 'func legacyGenerateBlock(')
methods = methods.replace('var image = generateRectsImage(color:', 'var image = legacyBlockRectsImage(color:')
helpers = []
for start_marker, end_marker in [('private enum CornerType {', 'public extension NSAttributedString.Key'), ('private func drawFullCorner(', 'public func generateRectsImage('), ('private func generateRectsImage(', 'public enum LinkHoverValue')]:
    start = baseline_text.index(start_marker)
    helpers.append(baseline_text[start:baseline_text.index(end_marker, start)])
helper_text = '\n'.join(helpers).replace('CornerType', 'LegacyBlockCornerType').replace('drawFullCorner', 'legacyBlockDrawFullCorner').replace('drawConnectingCorner', 'legacyBlockDrawConnectingCorner').replace('generateRectsImage', 'legacyBlockRectsImage')
reference = 'import Cocoa\nimport TGUIKit\nextension TextViewLayout {\n' + methods + '\n}\n' + helper_text
reference = '\n'.join(line for line in reference.splitlines() if not line.lstrip().startswith('//'))
assert reference.split() == (kit / 'Tests/TGUIKitTests/LegacyTextBlock.swift').read_text().split()
for name in ['Sources', 'Tests']:
    destination = output / 'TGUIKit' / name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(kit / name, destination)
manifest = (kit / 'Package.swift').read_text()
manifest = re.sub(r'(\.package\(name: "[^"]+", path: ")([^"]+)', lambda m: m[1] + str((kit / m[2]).resolve()), manifest)
(output / 'TGUIKit/Package.swift').write_text(manifest)
if variant == 'baseline':
    for name in ['TextView.swift']:
        (output / 'TGUIKit/Sources' / name).write_bytes(subprocess.check_output(['git', 'show', f'314247f46:packages/TGUIKit/Sources/{name}'], cwd=root))
destination = output / 'TextBlockLab/Sources'
if destination.exists():
    shutil.rmtree(destination)
shutil.copytree(lab / 'Sources', destination)
(output / 'TextBlockLab/Package.swift').write_text((lab / 'Package.swift').read_text().replace('../../../packages/TGUIKit', '../TGUIKit'))
paths = list((output / 'TGUIKit/Sources').glob('Text*.swift')) + list((destination / 'TextBlockLab').glob('*.swift'))
(output / 'provenance.json').write_text(json.dumps({'variant': variant, 'baseline': '314247f46', 'sha256': {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}, indent=2) + '\n')
