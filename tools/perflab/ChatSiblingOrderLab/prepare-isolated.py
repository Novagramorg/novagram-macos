from pathlib import Path
import gzip
import hashlib
import json
import shutil
import subprocess
import sys
lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists()
subprocess.run([sys.executable, str(lab / 'prepare.py')], check=True)
subprocess.run([sys.executable, str(root / 'tools/perflab/ChatLayerEngineLab/prepare-isolated.py'), str(output)], check=True)
engine = output / 'Sources/ChatLayerEngine'
baseline = output / 'Sources/SortingBaseline'
shutil.copytree(engine, baseline)
original = gzip.decompress((lab / 'Reference/ChatLayerScene.swift.gz').read_bytes())
(baseline / 'Generated/ChatLayerScene.swift').write_bytes(original)
inspection = (lab / 'Inspection.swift.txt').read_text()
for folder in [engine, baseline]:
    path = folder / 'Generated/ChatLayerScene.swift'
    path.write_text(path.read_text() + inspection)
shutil.copytree(lab / 'Tests/SiblingOrderTests', output / 'Tests/SiblingOrderTests')
path = output / 'Package.swift'
s = path.read_text()
marker = '        .target(name: "ChatLayerEngine", dependencies: ["TGUIKit", "InputTextView", "TelegramCore", .product(name: "SwiftSignalKit", package: "SSignalKit")]),'
assert s.count(marker) == 1
s = s.replace(marker, marker + '\n' + marker.replace('name: "ChatLayerEngine"', 'name: "SortingBaseline"') + '\n        .testTarget(name: "SiblingOrderTests", dependencies: ["ChatLayerEngine", "SortingBaseline", "TGUIKit"]),')
path.write_text(s)
candidate_sources = {str(p.relative_to(engine)): hashlib.sha256(p.read_bytes()).hexdigest() for p in engine.rglob('*') if p.is_file()}
baseline_sources = {str(p.relative_to(baseline)): hashlib.sha256(p.read_bytes()).hexdigest() for p in baseline.rglob('*') if p.is_file()}
assert candidate_sources.keys() == baseline_sources.keys()
differences = [name for name in candidate_sources if candidate_sources[name] != baseline_sources[name]]
assert differences == ['Generated/ChatLayerScene.swift'], differences
(output / 'sibling-order-comparison.json').write_text(json.dumps({'candidate': candidate_sources, 'baseline': baseline_sources, 'differences': differences}, indent=2) + '\n')
print(output)
