from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = 'a120843a3'
path = 'packages/PremiumStatusUI/Sources/PremiumStatusUI/PremiumStatusControl.swift'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()
output = 'import Cocoa\nimport TGUIKit\n'
for prefix, source in [('Reference', original), ('Candidate', current)]:
    output += source[source.index('protocol PremiumStatusRenderHost') if 'protocol PremiumStatusRenderHost' in source else source.index('public final class PremiumStatusControl :'):].replace('PremiumStatusControl', prefix + 'PremiumStatusControl') + '\n'
(lab / 'Tests/StatusTests/Generated.swift').write_text(output)
provenance = {'baseline': baseline, 'source': path, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}
layer_path = 'packages/InlineStickerLayer/Sources/InlineStickerLayer/InlineStickerItemLayer.swift'
layer = (root / layer_path).read_text()
start = layer.index('    public private(set) var file: TelegramMediaFile?')
end = layer.index('    public let fileId: Int64', start)
fields = layer[start:end].rstrip()
environment = (lab / 'Environment.swift.txt').read_text().replace('__FILE_RESOLUTION_FIELDS__', fields)
(lab / 'Tests/StatusTests/Environment.swift').write_text(environment)
provenance['layer_source'] = layer_path
provenance['layer_source_sha256'] = hashlib.sha256(layer.encode()).hexdigest()
provenance['resolution_fields_sha256'] = hashlib.sha256(fields.encode()).hexdigest()
provenance['environment_sha256'] = hashlib.sha256(environment.encode()).hexdigest()
(lab / 'generation.json').write_text(json.dumps(provenance, indent=2) + '\n')
