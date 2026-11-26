from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = '89e1ce0ee'
provenance = {'baseline': baseline, 'sources': {}}
for name in ['ImageView', 'TransformImageView']:
    path = 'packages/TGUIKit/Sources/' + name + '.swift'
    original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
    output = '@testable import TGUIKit\n' + original.replace(name, 'Reference' + name).replace('CaptureProtectedContentLayer', 'ReferenceCaptureProtectedContentLayer')
    (lab / 'Tests/ImageContentsTests' / ('Reference' + name + '.swift')).write_text(output)
    provenance['sources'][path] = {'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256((root / path).read_bytes()).hexdigest(), 'reference_sha256': hashlib.sha256(output.encode()).hexdigest()}
path = 'packages/ChatUI/Sources/ChatUI/ChatRightView.swift'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()
output = 'import Cocoa\nimport TGUIKit\n'
for prefix, source in [('Reference', original), ('Candidate', current)]:
    start = source.index('final class ChatRightIconLayer:')
    end = source.index('final class ChatRightTextLayer:', start)
    output += source[start:end].replace('ChatRightIconLayer', prefix + 'ChatRightIconLayer')
(lab / 'Tests/ImageContentsTests/IconLayers.swift').write_text(output)
provenance['sources'][path] = {'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest(), 'extracted_sha256': hashlib.sha256(output.encode()).hexdigest()}
(lab / 'generation.json').write_text(json.dumps(provenance, indent=2) + '\n')
