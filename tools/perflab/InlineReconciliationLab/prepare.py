from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
layer_path = root / 'packages/InlineStickerLayer/Sources/InlineStickerLayer/InlineStickerItemLayer.swift'
collection_path = root / 'packages/InlineStickerLayer/Sources/InlineStickerLayer/InlineStickerKeyCollection.swift'
callers = [root / p for p in [
    'Telegram-Mac/packages-integration/hooks/GeneralRowsHooksInstall.swift',
    'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift',
    'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatAccessoryModel.swift'
]]
layer = layer_path.read_text()
key = layer[layer.index('    public struct Key: Hashable {'):layer.index('    private let account: Account', layer.index('    public struct Key: Hashable {'))]
source = callers[0].read_text()
start = source.index('        var removeKeys: [InlineStickerItemLayer.Key]')
end = source.index('\n    }\n\n    func clear()', start)
cleanup = source[start:end]
reference = (lab / 'Reference.swift.txt').read_text()
for path in callers:
    assert 'var validIds = InlineStickerKeyCollection()' in path.read_text()
    assert 'if !validIds.contains(key)' in path.read_text()
output = 'import Cocoa\n\npublic final class InlineStickerItemLayer: CALayer {\n' + key + '}\n'
output += collection_path.read_text() + '\n'
for name, declaration, body in [('CurrentRows', 'var validIds = InlineStickerKeyCollection()', cleanup), ('ReferenceRows', 'var validIds: [InlineStickerItemLayer.Key] = []', reference)]:
    function = 'bind' + name
    body = body.replace('inlineStickerItemViews', 'row.inlineStickerItemViews')
    output += '@inline(never) func ' + function + '(_ row: LayerRows, _ keys: [InlineStickerItemLayer.Key]) {\n        ' + declaration + '\n        for id in keys {\n            validIds.append(id)\n            row.ensureLayer(id)\n        }\n' + body + '\n}\n'
    output += 'final class ' + name + ': LayerRows {\n    override func bind(_ keys: [InlineStickerItemLayer.Key]) { ' + function + '(self, keys) }\n}\n'
(lab / 'Sources/Reconciliation/Generated.swift').write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': '5ca1b89a6', 'source_sha256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [layer_path, collection_path] + callers}, 'key_sha256': hashlib.sha256(key.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
