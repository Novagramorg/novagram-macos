from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = 'packages/ShortPeerRow/Sources/ShortPeerRow/ShortPeerRowView.swift'
source = (root / path).read_text()
original = subprocess.check_output(['git', 'show', '623601c18:' + path], cwd=root).decode()

def binding(text):
    start = text.index('        if item.highlightVerified', text.index('    open override func set(item:'))
    status = text[start:text.index('        #endif', start)]
    start = text.index('        if let activity = item.inputActivity {', start)
    activity = text[start:text.index('        #endif', start)]
    return status + activity

reference = (lab / 'Reference.swift.txt').read_text()
assert reference == binding(original)
start = source.index('    private func updateStatusSubviewOrder()')
helper = source[start:source.index('    #endif', start)]
output = 'import Cocoa\nimport TGUIKit\n'
for name, body, methods in [('CurrentRow', binding(source), helper), ('ReferenceRow', reference, '')]:
    output += f'final class {name}: RowEnvironment {{\n    override func bind(_ item: RowItem, animated: Bool = false) {{\n{body}    }}\n{methods}}}\n'
target = lab / 'Sources/PeerRowTree/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
support = ['packages/TGUIKit/Sources/' + name for name in ['Control.swift', 'View.swift', 'AnimatableContentObserver.swift']]
(lab / 'provenance.json').write_text(json.dumps({'baseline': '623601c18', 'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'support_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in support}}, indent=2) + '\n')
