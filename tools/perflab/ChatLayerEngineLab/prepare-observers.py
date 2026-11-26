from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
source_path = 'packages/ChatUI/Sources/ChatUI/ChatRowView.swift'
source = (root / source_path).read_text()
original = subprocess.check_output(['git', 'show', '6a45ed29f:' + source_path], cwd=root, text=True)

def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

markers = ['    public override func set(item:TableRowItem, animated:Bool = false)', '    public override func viewDidMoveToWindow()', '    deinit {']
reference = '\n\n'.join(extract(original, marker) for marker in markers) + '\n'
reference = '\n'.join(line.rstrip() for line in reference.splitlines()) + '\n'
assert (lab / 'Reference/ChatRowObserver.swift.txt').read_text() == reference
output = 'import Cocoa\nimport TGUIKit\n\n'
for name, text in [('BaselineRow', original), ('CandidateRow', source)]:
    fields = ''
    if name == 'CandidateRow':
        fields = '\n'.join(line for line in text.splitlines() if 'private weak var observedInteraction:' in line or 'private var isPreparingItem:' in line)
        assert fields.count('\n') == 1
    methods = [extract(text, marker) for marker in markers]
    methods.append(extract(text, '    public func isEqual(to other: Notifable)'))
    methods.append(extract(text, '    public func notify(with value: Any, oldValue: Any, animated:Bool)'))
    if name == 'CandidateRow':
        methods.append(extract(text, '    private func updateInteractionObserver('))
    body = '\n\n'.join(methods).replace('public override func', 'override func').replace('public func notify', 'override func notify').replace('public func isEqual', 'override func isEqual').replace('as? ChatRowView', 'as? ' + name)
    body = '\n'.join(line.rstrip() for line in body.splitlines() if not line.lstrip().startswith('//'))
    output += 'final class ' + name + ': RowEnvironment {\n' + fields + '\n' + body + '\n}\n'
generated = lab / 'Sources/ChatRowObserverHarness/Generated'
generated.mkdir(parents=True, exist_ok=True)
(generated / 'Rows.swift').write_text(output)
(lab / 'observer-provenance.json').write_text(json.dumps({'baseline_commit': '6a45ed29f', 'source_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in [source_path, 'packages/TGUIKit/Sources/InterfaceObserver.swift']}, 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'scope': 'Complete production set(item:), notify, window lifecycle, deinit and observer helper; rendering and Telegram models are stand-ins. Actual TGUIKit InterfaceObserver and NSView window attachment.'}, indent=2) + '\n')
