from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = 'packages/TGUIKit/Sources/LinearProgressControl.swift'
reference = (lab / 'Reference.swift.txt').read_text()
assert reference == subprocess.check_output(['git', 'show', 'd0610bf3d:' + path], cwd=root).decode()
output = '@testable import TGUIKit\n' + reference.replace('LinearProgressControl', 'LegacyProgressControl').replace('LinearProgressAlignment', 'LegacyProgressAlignment')
target = lab / 'Sources/ProgressReference/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': 'd0610bf3d', 'production_sha256': hashlib.sha256((root / path).read_bytes()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
