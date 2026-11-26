from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) or output.is_relative_to(Path('/private/tmp'))
kit = root / 'packages/TGUIKit'
for name in ['Sources', 'Tests']:
    destination = output / 'TGUIKit' / name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(kit / name, destination)
manifest = (kit / 'Package.swift').read_text()
manifest = re.sub(r'(\.package\(name: "[^"]+", path: ")([^"]+)', lambda m: m[1] + str((kit / m[2]).resolve()), manifest)
(output / 'TGUIKit/Package.swift').write_text(manifest)
path = 'packages/TGUIKit/Sources/TextView.swift'
reference = subprocess.check_output(['git', 'show', 'bce10beff:' + path], cwd=root, text=True)
a = reference.index('    public override func draw(_ layer: CALayer, in ctx: CGContext) {', reference.index('open class TextView:'))
b = reference.index('    public override func rightMouseDown(', a)
reference_method = reference[a:b]
(lab / 'ReferenceDraw.swift.txt').write_text(reference_method)
method = reference_method.replace('lastDrawnSelectionState = currentSelectionState', 'labRecordSelectionDraw()').replace('self.blockHeaderRects = blockHeaderRects', 'self.referenceBlockHeaderRects = blockHeaderRects')
reference_class = '''
public final class LegacyTextRenderer: TextView {
    public var clearExceptRevealed = false
    public var inAnimation = false
    public var referenceBlockHeaderRects: [(NSRect, NSRange)] = []
''' + method + '}\n'
target = output / 'TGUIKit/Sources/TextView.swift'
test_access = """
extension TextView {
    public func labRecordSelectionDraw() { lastDrawnSelectionState = currentSelectionState }
    public var labHeaderRects: [(NSRect, NSRange)] { blockHeaderRects }
    public func labSetDrawFlags(revealed: Bool, animating: Bool) {
        clearExceptRevealed = revealed
        inAnimation = animating
    }
}
"""
target.write_text(target.read_text() + reference_class + test_access)
previous = subprocess.check_output(['git', 'show', 'f23a0ca31:' + path], cwd=root, text=True)
helper = previous[previous.index('private func drawTextViewContent('):previous.index('public final class TextViewLayer:')].replace('drawTextViewContent', 'drawPreviousTextViewContent')
start = previous.index('    public override func draw(_ layer: CALayer, in ctx: CGContext) {', previous.index('open class TextView:'))
end = previous.index('    public override func rightMouseDown(', start)
wrapper = previous[start:end].replace('drawTextViewContent', 'drawPreviousTextViewContent').replace('lastDrawnSelectionState = currentSelectionState', 'labRecordSelectionDraw()').replace('blockHeaderRects', 'referenceBlockHeaderRects')
previous_class = '''
public final class PreviousTextRenderer: TextView {
    public var clearExceptRevealed = false
    public var inAnimation = false
    public var referenceBlockHeaderRects: [(NSRect, NSRange)] = []
''' + wrapper + '}\n'
target.write_text(target.read_text() + helper + previous_class)
for name in ['Sources', 'Tests']:
    destination = output / 'TextViewLayerLab' / name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(lab / name, destination)
(output / 'TextViewLayerLab/Package.swift').write_text((lab / 'Package.swift').read_text().replace('../../../packages/TGUIKit', '../TGUIKit'))
chat_path = 'packages/ChatUI/Sources/ChatUI/ChatRightView.swift'
chat_reference = subprocess.check_output(['git', 'show', 'bce10beff:' + chat_path], cwd=root, text=True)
chat_current = (root / chat_path).read_text()
chat_output = 'import Cocoa\nimport TGUIKit\n'
for name, source in [('LegacyChatTextLayer', chat_reference), ('CurrentChatTextLayer', chat_current)]:
    block = source[source.index('final class ChatRightTextLayer:'):source.index('public class ChatRightView:')]
    chat_output += block.replace('ChatRightTextLayer', name)
(output / 'TextViewLayerLab/Sources/ChatTextRows/Generated.swift').write_text(chat_output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': 'bce10beff', 'previous_renderer_baseline': 'f23a0ca31', 'previous_renderer_sha256': hashlib.sha256((helper + previous_class).encode()).hexdigest(), 'production_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in [path, chat_path]}, 'reference_draw_sha256': hashlib.sha256(reference_method.encode()).hexdigest(), 'generated_reference_sha256': hashlib.sha256(reference_class.encode()).hexdigest(), 'generated_chat_sha256': hashlib.sha256(chat_output.encode()).hexdigest()}, indent=2) + '\n')
