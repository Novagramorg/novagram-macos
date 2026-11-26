from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = 'packages/TGUIKit/Sources/Extensions.swift'
baseline = 'b134e8654'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()
start = original.index('    static func initialize(string:')
end = original.index('    convenience init(string:', start)
reference = 'import Cocoa\nimport TGUIKit\nextension NSAttributedString {\n' + original[start:end].replace('func initialize(', 'func referenceInitialize(') + '}\n'
for signature, ending in [('    @discardableResult func append(string:', '    func add(link:'), ('    func setFont(font:', '\n}\n')]:
    old_start = original.index(signature)
    new_start = current.index(signature)
    assert original[old_start:original.index(ending, old_start)] == current[new_start:current.index(ending, new_start)]
(lab / 'Tests/FactoryTests/Reference.swift').write_text(reference)
(lab / 'generation.json').write_text(json.dumps({'baseline': baseline, 'source': path, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'append_and_set_font_unchanged': True}, indent=2) + '\n')
