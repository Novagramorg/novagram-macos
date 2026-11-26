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
subprocess.run([sys.executable, str(root / 'tools/perflab/ChatLayerEngineLab/prepare-isolated.py'), str(output)], check=True)
engine = output / 'Sources/ChatLayerEngine'
baseline = output / 'Sources/LayoutBaseline'
shutil.copytree(engine, baseline)
original = gzip.decompress((lab / 'Reference/ChatLayerScene.swift.gz').read_bytes())
(baseline / 'Generated/ChatLayerScene.swift').write_bytes(original)
metadata = json.loads((lab / 'Reference/provenance.json').read_text())
assert hashlib.sha256(original).hexdigest() == metadata['original_sha256']
candidate = original.decode()
for before, after in json.loads((lab / 'Reference/changes.json').read_text()):
    assert candidate.count(before) == 1
    candidate = candidate.replace(before, after)
assert hashlib.sha256(candidate.encode()).hexdigest() == metadata['candidate_sha256']
path = engine / 'Generated/ChatLayerScene.swift'
assert path.read_text() in [original.decode(), candidate]
path.write_text(candidate)
inspection = (lab / 'Inspection.swift.txt').read_text()
for folder in [engine, baseline]:
    path = folder / 'Generated/ChatLayerScene.swift'
    path.write_text(path.read_text() + inspection)
rowOriginal = gzip.decompress((lab / 'Reference/ChatLayerRowView.swift.gz').read_bytes())
rowMetadata = json.loads((lab / 'Reference/row-provenance.json').read_text())
assert hashlib.sha256(rowOriginal).hexdigest() == rowMetadata['original_sha256']
rowCandidate = rowOriginal.decode()
for before, after in json.loads((lab / 'Reference/row-changes.json').read_text()):
    assert rowCandidate.count(before) == 1
    rowCandidate = rowCandidate.replace(before, after)
assert hashlib.sha256(rowCandidate.encode()).hexdigest() == rowMetadata['candidate_sha256']
path = engine / 'Generated/ChatLayerRowView.swift'
assert path.read_text() in [rowOriginal.decode(), rowCandidate]
path.write_text(rowCandidate)
(baseline / 'Generated/ChatLayerRowView.swift').write_bytes(rowOriginal)
shutil.copytree(lab / 'Tests/SceneLayoutTests', output / 'Tests/SceneLayoutTests')
path = output / 'Package.swift'
s = path.read_text()
marker = '        .target(name: "ChatLayerEngine", dependencies: ["TGUIKit", "InputTextView", "TelegramCore", .product(name: "SwiftSignalKit", package: "SSignalKit")]),'
assert s.count(marker) == 1
s = s.replace(marker, marker + '\n' + marker.replace('name: "ChatLayerEngine"', 'name: "LayoutBaseline"') + '\n        .testTarget(name: "SceneLayoutTests", dependencies: ["ChatLayerEngine", "LayoutBaseline", "TGUIKit"]),')
path.write_text(s)
candidate_sources = {str(p.relative_to(engine)): hashlib.sha256(p.read_bytes()).hexdigest() for p in engine.rglob('*') if p.is_file()}
baseline_sources = {str(p.relative_to(baseline)): hashlib.sha256(p.read_bytes()).hexdigest() for p in baseline.rglob('*') if p.is_file()}
assert candidate_sources.keys() == baseline_sources.keys()
differences = [name for name in candidate_sources if candidate_sources[name] != baseline_sources[name]]
assert set(differences) == {'Generated/ChatLayerScene.swift', 'Generated/ChatLayerRowView.swift'}, differences
(output / 'scene-layout-comparison.json').write_text(json.dumps({'candidate': candidate_sources, 'baseline': baseline_sources, 'differences': differences}, indent=2) + '\n')
print(output)
