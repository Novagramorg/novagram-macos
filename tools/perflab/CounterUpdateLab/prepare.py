from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = '8f8c448ca'
path = 'packages/TGUIKit/Sources/DynamicCounterTextView.swift'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
reference = original.replace('import AppKit', 'import AppKit\n@testable import TGUIKit').replace('DynamicCounter', 'ReferenceDynamicCounter')
(lab / 'Tests/CounterUpdateTests/ReferenceCounter.swift').write_text(reference)
(lab / 'generation.json').write_text(json.dumps({'baseline': baseline, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256((root/path).read_bytes()).hexdigest()}, indent=2) + '\n')
