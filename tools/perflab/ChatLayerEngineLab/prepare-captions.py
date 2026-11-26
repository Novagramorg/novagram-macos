from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = 'packages/ChatUI/Sources/ChatUI/ChatRowView.swift'
source = (root / path).read_text()
original = subprocess.check_output(['git', 'show', '2e1e4125c:' + path], cwd=root, text=True)

def extract(text, marker):
    start = text.index('\n' + marker) + 1
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

native = subprocess.check_output(['git', 'show', 'df4acbdc0:' + path], cwd=root, text=True)

markers = ['    public class CaptionView {', '    public func fillCaption(']
reference = '\n\n'.join(extract(original, marker) for marker in markers) + '\n'
reference = '\n'.join(line.rstrip() for line in reference.splitlines()) + '\n'
assert (lab / 'Reference/ChatCaptionBinding.swift.txt').read_text() == reference
output = 'import Cocoa\nimport TGUIKit\nimport TelegramContext\n\n'
for name, text in [('ReplacementCaptionRow', original), ('ReusedCaptionRow', native)]:
    body = '\n\n'.join(extract(text, marker) for marker in markers).replace('public ', '').replace('func fillCaption(', 'override func fillCaption(')
    body = '\n'.join(line.rstrip() for line in body.splitlines())
    output += 'final class ' + name + ': CaptionRowEnvironment {\n    var captionViews: [CaptionView] = []\n'
    output += '    override var views: [FoldingTextView] { captionViews.map { $0.view } }\n'
    output += '    override var ids: [UInt32] { captionViews.map { $0.id } }\n'
    output += '    override var shimmers: [Bool] { captionViews.map { $0.shim } }\n'
    output += body + '\n}\n'
layer_markers = markers + ['    private final class CaptionBindingState {', '    private func updateCaptions(', '    var textSelectionSources:', '    public var selectableTextViews:', '    public func clickInContent(point:', '    public override func updateAnimatableContent()']
body = '\n\n'.join(extract(source, marker) for marker in layer_markers).replace('public ', '').replace('func fillCaption(', 'override func fillCaption(').replace('var textSelectionSources:', 'override var textSelectionSources:').replace('var selectableTextViews:', 'override var selectableTextViews:')
output += 'class LayerCaptionRow: CaptionRowEnvironment {\n    var captionViews: [CaptionView] = []\n    private var captionBindingState: CaptionBindingState?\n'
output += '    override var views: [FoldingTextView] { captionViews.compactMap { $0.nativeView } }\n'
output += '    override var contentViews: [View] { captionViews.map { $0.view } }\n'
output += '    override var ids: [UInt32] { captionViews.map { $0.id } }\n'
output += '    override var shimmers: [Bool] { captionViews.map { $0.shim } }\n'
output += body + '\n}\n'
output = output.replace('import TGUIKit\n', 'import TGUIKit\n@testable import ChatLayerEngine\n')
highlight_source = (root / 'packages/ChatUI/Sources/ChatUI/ChatLayerMessageText.swift').read_text()
output += '\nextension ChatLayerMessageTextNode {\n' + extract(highlight_source, '    func highlight(') + '\n}\n'
specialized_paths = []
for name in ['ChatInvoiceItem', 'ChatPollItem', 'ChatTodoItem']:
    specialized_path = 'packages/ChatUI/Sources/ChatUI/' + name + '.swift'
    specialized_paths.append(specialized_path)
    specialized = (root / specialized_path).read_text()
    output += '\nfinal class ' + name + 'CaptionSelection: LayerCaptionRow {\n'
    output += '    let textView = TextView()\n    final class Content { let titleView = CaptionFactCheck.Content() }\n    let contentNode = Content()\n'
    output += '\n'.join(extract(specialized, marker).replace('public ', '') for marker in ['    override var textSelectionSources:', '    public override var selectableTextViews:']) + '\n}\n'
(lab / 'Sources/FoldingViewHarness/Generated/Captions.swift').write_text(output)
paths = specialized_paths + ['packages/ChatUI/Sources/ChatUI/ChatMessageView.swift', 'packages/ChatUI/Sources/ChatUI/ChatLayerMessageText.swift', 'packages/ChatUI/Sources/ChatUI/ChatLayerMessageText+Layout.swift', path, 'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift', 'packages/TGUIKit/Sources/TextView.swift', str((lab / 'Sources/FoldingViewHarness/CaptionDependencies.swift').relative_to(root))]
(lab / 'caption-provenance.json').write_text(json.dumps({'baseline_commit': '2e1e4125c', 'native_reuse_commit': 'df4acbdc0', 'source_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths}, 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'scope': 'Exact current production caption wrapper, binding, selection and click methods plus layer highlight adapter; frozen native reuse control; full production FoldingTextView; real TGUIKit/AppKit. Row model, caption placement and media/account dependencies are stand-ins.'}, indent=2) + '\n')
