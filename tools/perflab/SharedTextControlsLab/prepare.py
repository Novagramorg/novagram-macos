from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = 'c2a11539d'
records = {}
for source, target, replacements in [
    ('TextViewLabel.swift', 'ReferenceLabel.swift', [('TextViewLabel', 'ReferenceTextViewLabel'), ('TextDelegate', 'ReferenceTextDelegate'), ('DrawLayer', 'ReferenceLabelDrawLayer')]),
    ('TitledBarView.swift', 'ReferenceTitle.swift', [('TitledBarView', 'ReferenceTitledBarView'), ('TitledContainerView', 'ReferenceTitledContainerView'), ('TitleBarImageSide', 'ReferenceTitleBarImageSide')])
]:
    path = 'packages/TGUIKit/Sources/' + source
    original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
    reference = original.replace('import Cocoa', 'import Cocoa\n@testable import TGUIKit')
    for before, after in replacements:
        reference = reference.replace(before, after)
    (lab / 'Tests/SharedTextControlsTests' / target).write_text(reference)
    records[path] = {'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256((root/path).read_bytes()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest()}
(lab / 'generation.json').write_text(json.dumps({'baseline': baseline, 'sources': records}, indent=2) + '\n')
