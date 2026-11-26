from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = '3d21a5571'
path = 'packages/TGUIKit/Sources/DynamicCounterTextView.swift'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
reference = original.replace('import AppKit', 'import AppKit\n@testable import TGUIKit').replace('DynamicCounterTextView', 'ReferenceDynamicCounterTextView')
(lab / 'Tests/CounterLayoutTests/ReferenceCounter.swift').write_text(reference)
(lab / 'generation.json').write_text(json.dumps({'baseline': baseline, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256((root/path).read_bytes()).hexdigest()}, indent=2) + '\n')
