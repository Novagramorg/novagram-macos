from pathlib import Path
import hashlib
import json
import shutil
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = root / 'packages/PremiumStatusUI/Sources/PremiumStatusUI/PremiumStatusControl.swift'
source = path.read_text()
start = 'public final class StarsEffectLayer:'
end = 'public final class PremiumStatusControl'
current = source[source.index(start):source.index(end)]
old = subprocess.check_output(['git', 'show', '2b88f9d2a:packages/PremiumStatusUI/Sources/PremiumStatusUI/PremiumStatusControl.swift'], cwd=root).decode()
reference = (lab / 'Reference.swift.txt').read_text()
assert old[old.index(start):old.index(end)] == reference
output = 'import AppKit\nimport TGUIKit\nimport QuartzCore\n'
for name, text in [('CandidateStarsEffectLayer', current), ('ReferenceStarsEffectLayer', reference)]:
    output += text.replace('StarsEffectLayer', name).replace('Bundle.main.path(forResource:', 'Bundle.module.path(forResource:')
target = lab / 'Sources/Effects/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
resource = lab / 'Sources/Effects/Resources/particle.png'
resource.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'Resources/premium/particle.png', resource)
(lab / 'provenance.json').write_text(json.dumps({'baseline': '2b88f9d2a', 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'particle_sha256': hashlib.sha256(resource.read_bytes()).hexdigest()}, indent=2) + '\n')
