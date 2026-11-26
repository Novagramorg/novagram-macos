from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = '343bbb304'
output = 'import Cocoa\nimport TGUIKit\n'
provenance = {'baseline': baseline, 'sources': {}}
for name in ['InteractiveTextView', 'InlineTextView']:
    path = 'packages/GeneralRows/Sources/GeneralRows/' + name + '.swift'
    original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
    current = (root / path).read_text()
    provenance['sources'][path] = {'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest()}
    for prefix, source in [('Reference', original), ('Candidate', current)]:
        output += source[source.index('public final class ' + name):].replace(name, prefix + name) + '\n'
(lab / 'Tests/InlineTextTests/Generated.swift').write_text(output)
provenance['generated_sha256'] = hashlib.sha256(output.encode()).hexdigest()
(lab / 'generation.json').write_text(json.dumps(provenance, indent=2) + '\n')
