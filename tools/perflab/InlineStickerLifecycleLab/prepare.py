from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = '828654359'
path = 'packages/InlineStickerLayer/Sources/InlineStickerLayer/InlineStickerItemLayer.swift'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()
output = 'import Cocoa\nimport TGUIKit\n'
for prefix, source in [('Reference', original), ('Candidate', current)]:
    start = source.index('public final class InlineStickerView:')
    end = source.index('public final class InlineStickerItemLayer :', start)
    output += source[start:end].replace('InlineStickerView', prefix + 'InlineStickerView')
(lab / 'Tests/InlineStickerTests/Generated.swift').write_text(output)
provenance = {'baseline': baseline, 'source': path, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}
(lab / 'generation.json').write_text(json.dumps(provenance, indent=2) + '\n')
