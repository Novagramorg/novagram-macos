import runpy
import subprocess
from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
sources = [root / 'packages/ChatUI/Sources/ChatUI' / name for name in ['ChatLayerScene.swift', 'ChatLayerTextNode.swift', 'ChatLayerButtonNode.swift', 'ChatLayerControlNode.swift', 'ChatBubbleTextSelection.swift', 'ChatLayerTextSelection.swift', 'ChatLayerMessageText.swift', 'ChatLayerMessageText+Layout.swift', 'ChatTextSelectionSource.swift', 'ChatLayerMessageTextView.swift', 'ChatLayerInlineEmoji.swift', 'ChatLayerTextLinkState.swift', 'ChatLayerRowView.swift']]
output = lab / 'Sources/ChatLayerEngine/Generated'
(lab / 'Sources/ChatLayerEngine/Generated.swift').unlink(missing_ok=True)
output.mkdir(parents=True, exist_ok=True)
for source in sources:
    (output / source.name).write_bytes(source.read_bytes())
message_reference = lab / 'Reference/MessageTextPreparation.swift.txt'
message_reference_hash = json.loads((lab / 'Reference/message-text-provenance.json').read_text())['captured_sha256']
assert hashlib.sha256(message_reference.read_bytes()).hexdigest() == message_reference_hash, 'Original message preparation reference changed'
(output / 'LegacyMessageTextPreparation.swift').write_text(message_reference.read_text().replace('ChatLayerMessageTextPresentation', 'LegacyChatLayerMessageTextPresentation'))
geometry_sources = [root / 'packages/ChatUI/Sources/ChatUI' / name for name in ['ChatRowGeometry.swift', 'ChatRowGeometry+Item.swift', 'ChatRowAccessoryGeometry.swift', 'ChatRowAccessoryGeometry+Item.swift']]
geometry_output = lab / 'Sources/ChatRowGeometryHarness/Generated'
geometry_output.mkdir(parents=True, exist_ok=True)
for source in geometry_sources:
    (geometry_output / source.name).write_bytes(source.read_bytes())
row_source = root / 'packages/ChatUI/Sources/ChatUI/ChatRowView.swift'
row_text = row_source.read_text()
def method(source, name):
    start = source.index('    public func ' + name + '(')
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]
names = ['invalidateFrameCache', 'cachedContentFrame', 'bubbleFrame', 'rightFrame', 'contentFrame']
reference = lab / 'Reference/ChatRowFrames.swift.txt'
reference_hash = json.loads((lab / 'Reference/geometry-provenance.json').read_text())['captured_methods_sha256']
assert hashlib.sha256(reference.read_bytes()).hexdigest() == reference_hash, 'Original geometry reference changed'
accessory_reference = lab / 'Reference/ChatRowAccessories.swift.txt'
accessory_provenance = json.loads((lab / 'Reference/accessory-provenance.json').read_text())
assert hashlib.sha256(accessory_reference.read_bytes()).hexdigest() == accessory_provenance['captured_methods_sha256'], 'Original accessory reference changed'
names += accessory_provenance['methods']
for kind, methods in [('Legacy', reference.read_text() + '\n' + accessory_reference.read_text()), ('Candidate', '\n\n'.join(method(row_text, name) for name in names))]:
    (geometry_output / (kind + 'ChatRowView.swift')).write_text('import Cocoa\n\npublic class ' + kind + 'ChatRowView: GeometryView {\n    var forwardAccessory: GeometryView?\n    private var _cachedBubbleFrame: NSRect?\n    private var _cachedContentFrame: NSRect?\n    private var _cachedRightFrame: NSRect?\n' + methods + '\n}\n')
folding_source = root / 'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift'
folding_text = folding_source.read_text()
start = folding_text.index('    public var size: NSSize {')
cursor = folding_text.index('{', start) + 1
depth = 1
while depth:
    depth += (folding_text[cursor] == '{') - (folding_text[cursor] == '}')
    cursor += 1
folding_output = lab / 'Sources/InputTextView/Generated'
folding_output.mkdir(parents=True, exist_ok=True)
(folding_output / 'Size.swift').write_text('import Cocoa\nimport TGUIKit\n\nextension FoldingTextLayout {\n' + folding_text[start:cursor] + '\n}\n')
def declaration(source, marker):
    start = source.index(marker)
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]
view_layout = declaration(folding_text, '    public struct ViewLayout {')
mask_function = declaration(folding_text, 'private final class FoldingQuoteMaskCache {') + '\n' + declaration(folding_text, 'private func renderFoldingQuoteMask(') + '\n' + declaration(folding_text, 'private func generateMaskImage(')
wrapper = declaration(folding_text, 'private final class WrapperView : View')
interaction_protocol = declaration(folding_text, 'private protocol FoldingBlockInteractionState: AnyObject {')
quote_icon = declaration(folding_text, 'private let quoteIcon: CGImage = {') + '()\n'
quote_text = 'import Cocoa\nimport TGUIKit\n\n' + quote_icon + '\n' + declaration(folding_text, 'public final class FoldingTextQuoteLayer: SimpleLayer {') + '\n'
reference_wrapper = lab / 'Reference/FoldingWrapper.swift.txt'
assert hashlib.sha256(reference_wrapper.read_bytes()).hexdigest() == json.loads((lab / 'Reference/folding-wrapper-provenance.json').read_text())['captured_sha256']
original_painter = declaration(reference_wrapper.read_text(), '    class BlockLayer: SimpleLayer {')
current_painter = declaration(folding_text, 'public final class FoldingTextQuoteLayer: SimpleLayer {').replace('public final class FoldingTextQuoteLayer', 'class BlockLayer').replace('FoldingTextQuoteLayer)', 'BlockLayer)').replace('public var blockQuotes', 'var blockQuotes').replace('public override func draw', 'override func draw')
verified_painter = current_painter.replace(declaration(current_painter, '    private final class CopyIconCache {'), '')
verified_painter = verified_painter.replace(declaration(verified_painter, '    private struct DrawingState {'), '')
verified_painter = verified_painter.replace('    private var drawingState: DrawingState?\n', '')
verified_painter = verified_painter.replace(declaration(verified_painter, '    public override func display() {'), '')
verified_painter = verified_painter.replace(declaration(verified_painter, '    public override var bounds: CGRect {'), '')
verified_painter = verified_painter.replace(declaration(verified_painter, '    public override var contentsScale: CGFloat {'), '')
verified_painter = verified_painter.replace('            if contents == nil || drawingState?.matches(self) != true {\n                setNeedsDisplay()\n            }', '            setNeedsDisplay()')
verified_painter = verified_painter.replace('CopyIconCache.shared.image(TelegramThemeHooks.shared.image(.iconCopyCode), color: blockQuote.colors.main, scale: System.backingScale)', 'TelegramThemeHooks.shared.image(.iconCopyCode).precomposed(blockQuote.colors.main, flipVertical: true)')
assert [line.strip() for line in original_painter.splitlines() if line.strip()] == [line.strip() for line in verified_painter.splitlines() if line.strip()], 'Shared quote painter changed beyond the verified icon cache'
(folding_output / 'QuoteLayer.swift').write_text(quote_text)
wrapper = reference_wrapper.read_text() + '\n' + wrapper.replace('WrapperView', 'CandidateWrapperView')
native_factory = '''
public func makeReferenceFoldingWrapper(_ layout: FoldingTextLayout.ViewLayout) -> View {
    let view = WrapperView(frame: CGRect(origin: .zero, size: layout.size))
    view.update(layout, isRevealed: layout.isRevealed, context: ReferenceContext(), transition: .immediate)
    return view
}
public func updateReferenceFoldingWrapper(_ view: View, layout: FoldingTextLayout.ViewLayout) {
    (view as! WrapperView).update(layout, isRevealed: layout.isRevealed, context: ReferenceContext(), transition: .immediate)
}
public func isReferenceFoldingWrapper(_ view: View) -> Bool { view is WrapperView }
public func makeCandidateFoldingWrapper(_ layout: FoldingTextLayout.ViewLayout) -> View {
    let view = CandidateWrapperView(frame: CGRect(origin: .zero, size: layout.size))
    view.update(layout, isRevealed: layout.isRevealed, context: ReferenceContext(), transition: .immediate)
    return view
}

public func updateCandidateFoldingWrapper(_ view: View, layout: FoldingTextLayout.ViewLayout, transition: ContainedViewLayoutTransition) {
    (view as! CandidateWrapperView).update(layout, isRevealed: layout.isRevealed, context: ReferenceContext(), transition: transition)
}
'''
(folding_output / 'QuoteWrapper.swift').write_text('import Cocoa\nimport TGUIKit\n\n' + quote_icon + mask_function + '\n\nextension FoldingTextLayout {\n' + view_layout + '\n}\n\n' + interaction_protocol + '\n' + wrapper + '\n' + native_factory)
selection_source = root / 'packages/ChatUI/Sources/ChatUI/ChatSelectText.swift'
selection_text = selection_source.read_text()
selection_reference = lab / 'Reference/SelectManager.swift.txt'
assert hashlib.sha256(selection_reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/selection-manager-provenance.json').read_text())['captured_sha256']
start = selection_text.index('public class SelectManager')
end = selection_text.index('    /// The selected attributed text of ONE rich message', start)
selection_prefix = declaration(selection_text, 'public struct SelectContainer') + '\n' + selection_text[start:end] + '}\n'
selection_helpers = r"""
func preserveBubbleSelection(_ manager: SelectManager, stableId: AnyHashable) -> () -> Void {
    let snapshot = manager.currentBubbleRanges()[stableId] ?? []
    return { manager.restoreBubbleRanges(snapshot) }
}
func bubbleSelectionSummary(_ manager: SelectManager, stableId: AnyHashable) -> [(index: Int, hasSource: Bool, rich: Bool)] {
    return (manager.currentBubbleRanges()[stableId] ?? []).map { ($0.2.index, $0.1.source != nil, $0.1.isRichText) }
}
"""
selector_reference = lab / 'Reference/ChatSelectTextRunSelector.swift.txt'
assert hashlib.sha256(selector_reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/selection-manager-provenance.json').read_text())['selector_sha256']
embedded_selection_reference = lab / 'Reference/EmbeddedTextSelection.swift.txt'
assert hashlib.sha256(embedded_selection_reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/embedded-selection-provenance.json').read_text())['sha256']
selectors = ''
for name, manager, method in [('SelectionLoopHarness', 'SelectManager', declaration(selection_text, '    private func runSelector(')), ('LegacySelectionLoopHarness', 'LegacySelectManager', selector_reference.read_text()), ('ReferenceEmbeddedSelectionLoopHarness', 'SelectManager', embedded_selection_reference.read_text())]:
    selectors += 'final class ' + name + ' {\n' + '    let selectManager = ' + manager + '()\n' + r"""
    let table: SelectionTable
    var beginInnerLocation = NSPoint.zero
    var endInnerLocation = NSPoint.zero
    var deselect = false
    var reversible = false
    init(_ table: SelectionTable) { self.table = table }
    func select(begin: NSPoint, end: NSPoint, window: Window, reversedTable: Bool = true) {
        beginInnerLocation = begin
        endInnerLocation = end
        reversible = !reversedTable
        runSelector(window: window, chatInteraction: ChatInteraction())
    }
""" + method + '\n}\n'
(output / 'SelectManager.swift').write_text('import Cocoa\nimport TGUIKit\nimport SwiftSignalKit\nimport TelegramCore\n\n' + selection_prefix + selection_helpers + '\n' + selection_reference.read_text().replace('SelectManager', 'LegacySelectManager') + '\n' + declaration(selection_text, 'public protocol MultipleSelectable') + '\n' + selectors)
(lab / 'provenance.json').write_text(json.dumps({'production_sha256': {str(source.relative_to(root)): hashlib.sha256(source.read_bytes()).hexdigest() for source in sources + geometry_sources + [row_source, folding_source, selection_source, root / 'packages/TGUIKit/Sources/TextView.swift']}}, indent=2) + '\n')

blocks_reference = lab / 'Reference/FoldingBlocks.swift.txt'
assert hashlib.sha256(blocks_reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/folding-blocks-provenance.json').read_text())['captured_sha256']
blocks_output = lab / 'Sources/FoldingBlocksHarness/Generated'
blocks_output.mkdir(parents=True, exist_ok=True)
for legacy, contents in [(False, folding_text[folding_text.index('private final class FoldingInlineStickers {'):folding_text.index('public class FoldingTextView : View {')]), (True, blocks_reference.read_text())]:
    name = 'Legacy' if legacy else 'Current'
    factory = """
func makeNAMEBlock(quoted: Bool) -> BlockHarness {
    if quoted {
        let block = WrapperView(frame: .zero)
        return BlockHarness(owner: block, view: block, textView: block.textView, update: { layout, context in
            block.update(layout, isRevealed: layout.isRevealed, context: context, transition: .immediate)
        }, listeners: {
            block.viewDidMoveToSuperview()
        })
    } else {
        let block = PlainTextBlock()
        return BlockHarness(owner: block, view: block.textView, textView: block.textView, update: { layout, context in
            block.update(layout, context: context, transition: .immediate)
            block.updateListeners()
        }, listeners: { block.updateListeners() })
    }
}
""".replace('NAME', name)
    (blocks_output / (name + '.swift')).write_text('import Cocoa\nimport TGUIKit\nimport InputTextView\n\n' + contents + factory)
playback_source = root / 'packages/InlineStickerLayer/Sources/InlineStickerLayer/InlineStickerPlayback.swift'
keys_source = root / 'packages/InlineStickerLayer/Sources/InlineStickerLayer/InlineStickerKeyCollection.swift'
playback_text = playback_source.read_text().replace('updateInlineStickerPlayback', 'performInlineStickerPlayback')
keys_text = keys_source.read_text()
for prefix in ['@inlinable ', '@usableFromInline ', 'public ']:
    playback_text = playback_text.replace(prefix, '')
    keys_text = keys_text.replace(prefix, '')
(blocks_output / 'Playback.swift').write_text(playback_text)
(blocks_output / 'Keys.swift').write_text(keys_text)
blocks_provenance = {'production_sha256': {str(source.relative_to(root)): hashlib.sha256(source.read_bytes()).hexdigest() for source in [folding_source, playback_source, keys_source, root / 'packages/TGUIKit/Sources/AnimatableContentObserver.swift']}}
(lab / 'folding-blocks-provenance.json').write_text(json.dumps(blocks_provenance, indent=2) + '\n')

view_reference = lab / 'Reference/FoldingTextView.swift.txt'
assert hashlib.sha256(view_reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/folding-view-provenance.json').read_text())['captured_sha256']
view_output = lab / 'Sources/FoldingViewHarness/Generated'
view_output.mkdir(parents=True, exist_ok=True)
for legacy, contents in [(False, folding_text), (True, view_reference.read_text())]:
    name = 'Legacy' if legacy else 'Current'
    contents = '\n'.join(line for line in contents.splitlines() if not line.startswith('import ')).replace('public ', '')
    if legacy:
        contents = contents.replace('FoldingText', 'LegacyFoldingText')
    (view_output / (name + '.swift')).write_text('import Cocoa\nimport TGUIKit\nimport TelegramContext\n' + contents)
view_dependencies = (lab / 'Sources/FoldingBlocksHarness/Dependencies.swift').read_text().split('final class BlockHarness {')[0].replace('import InputTextView\n', '')
view_dependencies = view_dependencies.replace('enum LiteMode { case emoji }\n', '').replace(declaration(view_dependencies, 'protocol AccountContextProtocol: AnyObject {') + '\n', '')
view_dependencies = view_dependencies.replace('var account = 0', 'var account = TelegramContext.Account()').replace('var inlinePacksContext = 0', 'var inlinePacksContext = TelegramContext.InlineStickersContext()')
view_dependencies = view_dependencies.replace('init(account: Int, inlinePacksContext: Int,', 'init(account: TelegramContext.Account, inlinePacksContext: TelegramContext.InlineStickersContext,')
(view_output / 'Dependencies.swift').write_text('import TelegramContext\n' + view_dependencies)
(view_output / 'Playback.swift').write_text(playback_text)
(view_output / 'Keys.swift').write_text(keys_text)

view_provenance_sources = [folding_source, root / 'packages/TGUIKit/Sources/TextView.swift', root / 'packages/TGUIKit/Sources/Control.swift', root / 'packages/TGUIKit/Sources/DisplayLinkAnimator.swift', lab / 'Sources/FoldingBlocksHarness/Dependencies.swift', lab / 'Sources/FoldingViewHarness/AnimationDependencies.swift', playback_source, keys_source]
(lab / 'folding-view-provenance.json').write_text(json.dumps({'production_and_stand_in_sha256': {str(source.relative_to(root)): hashlib.sha256(source.read_bytes()).hexdigest() for source in view_provenance_sources}, 'baseline': 'd02da2792', 'transforms': ['remove external imports', 'remove public visibility', 'prefix baseline FoldingText type names with Legacy']}, indent=2) + '\n')

text_binding_reference = lab / 'Reference/ChatMessageTextBinding.swift.txt'
assert hashlib.sha256(text_binding_reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/chat-text-binding-provenance.json').read_text())['sha256']
text_binding_source = root / 'packages/ChatUI/Sources/ChatUI/ChatMessageView.swift'
text_binding = declaration(text_binding_source.read_text(), '    private func updateNativeText(').replace('private func updateNativeText', 'func updateText')
native_binding_reference = lab / 'Reference/NativeMessageTextBinding.swift.txt'
assert hashlib.sha256(native_binding_reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/native-message-binding-provenance.json').read_text())['sha256']
for name, binding in [('ReplacementChatTextRow', text_binding_reference.read_text()), ('ReusedChatTextRow', text_binding), ('PreviousNativeChatTextRow', native_binding_reference.read_text())]:
    (lab / 'Sources/FoldingViewHarness/Generated' / (name + '.swift')).write_text('import Cocoa\nimport TGUIKit\n\nfinal class ' + name + ': ChatTextRow {\n    override func bind(_ next: ChatMessageItem, animated: Bool = false) {\n        let previous = item as? ChatMessageItem\n        item = next\n        updateText(for: next, previous: previous, animated: animated)\n    }\n' + binding + '\n' + declaration(text_binding_source.read_text(), '    public override var selectableTextViews:') + '\n}\n')

plain_text_adapter = (root / 'packages/ChatUI/Sources/ChatUI/ChatLayerMessageText+Layout.swift').read_text()
plain_text_methods = '\n\n'.join(declaration(plain_text_adapter, marker) for marker in ['    private enum AttributeKeys {', '    @inline(__always)', '    private static func supportsInlineEmoji(', '    static func simpleText('])
(lab / 'Sources/FoldingViewHarness/Generated/PlainTextPreparation.swift').write_text('import Cocoa\nimport TGUIKit\nimport InputView\nimport InlineStickerLayer\n@testable import ChatLayerEngine\n\nextension ChatLayerMessageTextPresentation {\n' + plain_text_methods.replace('as? InlineStickerItem', 'as? InlineStickerLayer.InlineStickerItem') + '\n}\n')

live_text = text_binding_source.read_text()
live_methods = '\n\n'.join(declaration(live_text, marker) for marker in ['    private func updateText(', '    private func updateNativeText(', '    func firstTextBaseline(', '    public override var selectableTextViews:', '    override var textSelectionSources:', '    public override func updateAnimatableContent()'])
(lab / 'Sources/FoldingViewHarness/Generated/LayerChatTextRow.swift').write_text('import Cocoa\nimport TGUIKit\n@testable import ChatLayerEngine\n\nfinal class LayerChatTextRow: ChatTextRow {\n' + declaration(live_text, '    var textContentView:') + '\n    override func bind(_ next: ChatMessageItem, animated: Bool = false) {\n        textBindingVersion &+= 1\n        let previous = item as? ChatMessageItem\n        item = next\n        updateText(for: next, previous: previous, animated: animated)\n    }\n' + live_methods + '\n}\n')

outer_text_layout = declaration(live_text[live_text.index('    public override func updateLayout('):], '        if let text = textContentView {')
with (lab / 'Sources/FoldingViewHarness/Generated/LayerChatTextRow.swift').open('a') as stream:
    stream.write('\nextension LayerChatTextRow {\n    func finishLayout(transition: ContainedViewLayoutTransition = .immediate) {\n        guard let item = item as? ChatMessageItem else { return }\n' + outer_text_layout + '\n        textContentView?.layoutSubtreeIfNeeded()\n    }\n}\n')

runpy.run_path(str(lab / "prepare-observers.py"))
runpy.run_path(str(lab / "prepare-captions.py"))

highlight_method = declaration(folding_text, '    public func highlight(text: String, color: NSColor, range: NSRange? = nil)')
(folding_output / 'HighlightReference.swift').write_text('import Cocoa\nimport TGUIKit\n\npublic final class NativeMessageHighlightHarness {\n    let layouts: FoldingTextLayout?\n    let textViews: [TextView]\n    public init(layouts: FoldingTextLayout, textViews: [TextView]) { self.layouts = layouts; self.textViews = textViews }\n' + highlight_method + '\n}\n')

highlight_baseline = subprocess.check_output(['git', 'show', '0d986d65f:packages/ChatUI/Sources/ChatUI/ChatLayerTextNode.swift'], cwd=root, text=True)
(output / 'ReferenceHighlightTextNode.swift').write_text(highlight_baseline.replace('ChatLayerTextNode', 'ReferenceHighlightTextNode'))

menu_baseline = subprocess.check_output(['git', 'show', 'a98fe5c6d:packages/ChatUI/Sources/ChatUI/ChatLayerTextNode.swift'], cwd=root, text=True)
(output / 'ReferenceMenuTextNode.swift').write_text(menu_baseline.replace('ChatLayerTextNode', 'ReferenceMenuTextNode'))

reentrancy_baseline = subprocess.check_output(['git', 'show', '7e69ec48e:packages/ChatUI/Sources/ChatUI/ChatLayerTextNode.swift'], cwd=root, text=True)
(output / 'ReferenceReentrancyTextNode.swift').write_text(reentrancy_baseline.replace('ChatLayerTextNode', 'ReferenceReentrancyTextNode'))

message_binding_baseline = subprocess.check_output(['git', 'show', '8f78986bf:packages/ChatUI/Sources/ChatUI/ChatLayerMessageText.swift'], cwd=root, text=True)
message_binding_class = message_binding_baseline[message_binding_baseline.index('final class ChatLayerMessageTextNode:'):]
(output / 'ReferenceMessageBindingNode.swift').write_text('import Cocoa\nimport TGUIKit\nimport InputTextView\n\n' + message_binding_class.replace('ChatLayerMessageTextNode', 'ReferenceMessageBindingNode'))

message_binding_prepass = (lab / 'results/message-binding/prepass-candidate.swift.txt').read_text()
message_binding_prepass_class = message_binding_prepass[message_binding_prepass.index('final class ChatLayerMessageTextNode:'):]
(output / 'PrepassMessageBindingNode.swift').write_text('import Cocoa\nimport TGUIKit\nimport InputTextView\n\n' + message_binding_prepass_class.replace('ChatLayerMessageTextNode', 'PrepassMessageBindingNode'))

header_baseline = subprocess.check_output(['git', 'show', '778589c29:packages/ChatUI/Sources/ChatUI/ChatRowView.swift'], cwd=root, text=True)
header_current = row_source.read_text()
header_fixture = """import Cocoa
import TGUIKit

final class HeaderBindingItem {
    let forwardHeader: TextViewLayout?
    let frame: NSRect
    init(_ layout: TextViewLayout?, frame: NSRect) { forwardHeader = layout; self.frame = frame }
}
"""
for name, source, host, property in [('NativeHeaderBindingRow', header_baseline, 'View', 'var forwardHeader: TextView?'), ('LayerHeaderBindingRow', header_current, 'ChatLayerRowView', '')]:
    assert 'rowView = ' + host + '(frame:' in source, 'Row host does not match production initializer'
    binding = declaration(source, '    public func fillForwardHeader(').replace('public func', 'func').replace('ChatRowItem', 'HeaderBindingItem')
    header_fixture += """
final class %s: View {
    let rowView: View
    %s
    required init(frame: NSRect) {
        rowView = %s(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
    }
    required init?(coder: NSCoder) { fatalError() }
    func forwardHeaderRect(_ item: HeaderBindingItem) -> NSRect { item.frame }
%s
}
""" % (name, property, host, binding)
    if name == 'NativeHeaderBindingRow':
        placement = declaration(source, '        if let view = forwardHeader {')
    else:
        placement = next(line for line in source.splitlines() if '?.layoutForwardHeader(frame:' in line)
    header_fixture += '\nextension ' + name + ' {\n    func layoutHeader(_ item: HeaderBindingItem, transition: ContainedViewLayoutTransition) {\n' + placement + '\n    }\n}\n'
(output / 'HeaderBinding.swift').write_text(header_fixture)

badge_fixture = """import Cocoa
import TGUIKit

final class BadgeBindingItem {
    let adminBadge: TextViewLayout
    let adminBadgeAuthorId: Int?
    var actions = 0
    init(_ layout: TextViewLayout, authorId: Int?) { adminBadge = layout; adminBadgeAuthorId = authorId }
    func adminBadgeInteraction(_ view: NSView) { actions += 1 }
}
"""
for name, source in [('NativeBadgeBindingRow', header_baseline), ('LayerBadgeBindingRow', header_current)]:
    start = source.index('                    if self.adminBadge == nil {')
    end = source.index('                    if item.adminBadgeIsRank,', start)
    badge_fixture += """
final class %s: View {
    var adminBadge: TextView?
    var rowView: View { self }
    func adminBadgePoint(_ item: BadgeBindingItem) -> NSPoint { .zero }
    func bind(_ item: BadgeBindingItem) {
        let adminBadge = item.adminBadge
%s
    }
}
""" % (name, source[start:end])
(output / 'BadgeBinding.swift').write_text(badge_fixture)


sender_baseline = subprocess.check_output(['git', 'show', 'f99d1ddde:packages/ChatUI/Sources/ChatUI/ChatRowView.swift'], cwd=root, text=True)
sender_fixture = """import Cocoa
import TGUIKit

final class HostedRightStub: View {
    var isContentHosted: Bool { false }
}

final class SenderBindingItem {
    var authorText: TextViewLayout?
    var nameHide: String?
    var isBubbled = true
    var hasBubble = true
    var boostBadge: TextViewLayout?
    var adminBadge: TextViewLayout?
    var adminBadgeAuthorId: Int?
    var adminBadgeIsRank = false
    var adminBadgeColor: NSColor?
    var guestChatBadge: TextViewLayout?
    let context = 0
    init(_ layout: TextViewLayout?, toolTip: String? = nil) { authorText = layout; nameHide = toolTip }
    var badgeActions: [NSView] = []
    func boost(morphSource: () -> NSView?) {}
    func adminBadgeInteraction(_ view: NSView) { badgeActions.append(view) }
}
final class SenderViaAccessory: View {
    func updateText(layout: TextViewLayout) {}
}
final class SenderInteractiveTextView: Control {
    let textView = TextView()
    func set(text: TextViewLayout, context: Int, emojiOffset: NSPoint = .zero) { textView.update(text) }
}
struct SenderCaption { let view: View }
"""
for name, source, host, property in [('NativeSenderBindingRow', sender_baseline, 'View', 'var nameView: TextView?'), ('LayerSenderBindingRow', row_source.read_text(), 'ChatLayerRowView', '')]:
    binding = declaration(source, '    public func fillName(').replace('public func', 'func').replace('ChatRowItem', 'SenderBindingItem').replace('ChatBubbleViaAccessory', 'SenderViaAccessory').replace('InteractiveTextView', 'SenderInteractiveTextView')
    shake = declaration(source, '    public func shakeContentView(').replace('public func', 'func').replace('ChatRowItem', 'SenderBindingItem')
    placement = declaration(source, '        if let view = nameView {') if name == 'NativeSenderBindingRow' else next(line for line in source.splitlines() if '?.layoutSenderName(origin:' in line)
    if name == 'NativeSenderBindingRow':
        placement = declaration(source[source.index('    public override func updateLayout(size:'):], '        if let view = nameView {')
    background = next(line for line in source.splitlines() if 'nameView?.backgroundColor =' in line or '?.senderName?.layer.backgroundColor =' in line)
    sender_fixture += """
final class %s: View {
    let rowView: View
    let bubbleView = View()
    let contentView = View()
    let rightView = HostedRightStub()
    func moveHostedRightForShake() -> (() -> Void)? { nil }
    var statusControl: View?, forwardStatusControl: View?, replyView: View?, forwardName: View?, forwardPhoto: View?
    var replyNode: ChatLayerControlNode?
    var captionViews: [SenderCaption] = []
    var item: Any?
    %s
    var viaAccessory: SenderViaAccessory?
    var adminBadge: TextView?
    var adminBadgeBg: View?
    var boostBadge: SenderInteractiveTextView?
    var ephemeralBadgeView: SenderInteractiveTextView?
    required init(frame: NSRect) {
        rowView = %s(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
        rowView.addSubview(bubbleView)
        rowView.addSubview(contentView)
        (rowView as? ChatLayerRowView)?.layerHitBackground = bubbleView
    }
    required init?(coder: NSCoder) { fatalError() }
    func namePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 25, y: 20) }
    func boostBadgePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 220, y: 20) }
    func adminBadgePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 230, y: 20) }
    func adminBadgeBgRect(_ item: SenderBindingItem) -> NSRect { NSRect(x: 225, y: 18, width: 40, height: 20) }
    var badgeNodes = false
    func usesAdminBadgeNode(_ item: SenderBindingItem) -> Bool { badgeNodes && rowView is ChatLayerRowView }
    func ephemeralBadgePoint(_ item: SenderBindingItem) -> NSPoint { .zero }
    func bubbleFrame(_ item: SenderBindingItem) -> NSRect { NSRect(x: 10, y: 10, width: 270, height: 90) }
    func contentFrameModifier(_ item: SenderBindingItem) -> NSRect { NSRect(x: 25, y: 55, width: 200, height: 30) }
    func bind(_ item: SenderBindingItem, animated: Bool = false) {
        self.item = item
        bubbleView.frame = bubbleFrame(item)
        contentView.frame = contentFrameModifier(item)
        fillName(item, animated: animated)
    }
    func layoutName(_ item: SenderBindingItem, transition: ContainedViewLayoutTransition = .immediate) {
%s
    }
    func updateNameBackground(_ contentColor: NSColor) {
%s
    }
%s
%s
}
""" % (name, property, host, placement, background, binding, shake)
(output / 'SenderBinding.swift').write_text(sender_fixture)


routing_baseline = subprocess.check_output(['git', 'show', '8be40ed65:packages/ChatUI/Sources/ChatUI/ChatLayerScene.swift'], cwd=root, text=True)
for symbol in ['ChatLayerAccessibilityElement', 'ChatLayerSceneView', 'ChatLayerTextNode', 'ChatLayerPointerEvent', 'ChatLayerTreeError', 'ChatLayerNode']:
    routing_baseline = routing_baseline.replace(symbol, 'Reference' + symbol)
routing_baseline += """
extension ReferenceChatLayerSceneView {
    func clearBubbleSelection() {}
}
final class ReferenceChatLayerTextNode: ReferenceChatLayerNode {
    func synchronizeLinkToolTips(force: Bool) {}
    func didRemoveLinkToolTips() {}
    func refreshLinkHover(at point: NSPoint) {}
}
final class ReferenceRowInteractionView: ReferenceChatLayerSceneView {
    weak var layerHitBackground: NSView?
    required init(frame: NSRect) { super.init(frame: frame, deferred: true) }
    required init?(coder: NSCoder) { fatalError() }
"""
routing_host = subprocess.check_output(['git', 'show', '8be40ed65:packages/ChatUI/Sources/ChatUI/ChatLayerRowView.swift'], cwd=root, text=True)
for marker in ['    override func hitNode(', '    override func hitTest(', '    override func updatePointerCursor(']:
    routing_baseline += declaration(routing_host, marker).replace('ChatLayerNode', 'ReferenceChatLayerNode') + '\n'
routing_baseline += '}\n'
(output / 'ReferenceRowInteraction.swift').write_text(routing_baseline)


forward_baseline = subprocess.check_output(['git', 'show', 'e2ae34ce8:packages/ChatUI/Sources/ChatUI/ChatRowView.swift'], cwd=root, text=True)
forward_host_baseline = subprocess.check_output(['git', 'show', 'e2ae34ce8:packages/ChatUI/Sources/ChatUI/ChatLayerRowView.swift'], cwd=root, text=True)
(output / 'BeforeForwardNameRowView.swift').write_text(forward_host_baseline.replace('ChatLayerRowView', 'BeforeForwardNameRowView'))
forward_fixture = """import Cocoa
import TGUIKit

struct ForwardBindingContext { let account = 0 }
struct ForwardBindingInfo { let author: Int }
struct ForwardBindingMessage { let forwardInfo: ForwardBindingInfo? }
final class ForwardBindingItem {
    var forwardNameLayout: TextViewLayout?
    var forwardPhotoPlaceRange: NSRange?
    var isBubbled = true
    var hasBubble = true
    let context = ForwardBindingContext()
    var message: ForwardBindingMessage? = ForwardBindingMessage(forwardInfo: ForwardBindingInfo(author: 42))
    var actions = 0
    init(_ layout: TextViewLayout?, photo: Bool = false) {
        forwardNameLayout = layout
        forwardPhotoPlaceRange = photo ? NSRange(location: 1, length: 2) : nil
    }
    func openForwardInfo() { actions += 1 }
}
final class ForwardBindingAvatar: Control {
    private(set) var peer: Int?
    init(font: NSFont) {
        super.init(frame: .zero)
        backgroundColor = .systemOrange
        layer?.cornerRadius = 7
    }
    required init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    func setPeer(account: Int, peer: Int?, message: ForwardBindingMessage?) { self.peer = peer }
}
final class ForwardBindingAccessory: View {
    private(set) var text: TextViewLayout?
    func updateText(layout: TextViewLayout, replyView: View?) { text = layout }
}
struct ForwardTooltipCapture {
    weak var view: NSView?
    let rect: NSRect
    let text: String
    let autoCorner: Bool
}
var forwardTooltipCapture: ForwardTooltipCapture?
func recordForwardTooltip(for view: NSView, text: String, autoCorner: Bool, rect: NSRect? = nil) {
    forwardTooltipCapture = ForwardTooltipCapture(view: view, rect: rect ?? view.bounds, text: text, autoCorner: autoCorner)
}
"""
for name, source, host, property in [('NativeForwardBindingRow', forward_baseline, 'BeforeForwardNameRowView', 'var forwardName: TextView?'), ('LayerForwardBindingRow', row_source.read_text(), 'ChatLayerRowView', '')]:
    binding = declaration(source, '    public func fillForward(').replace('public func', 'func').replace('ChatRowItem', 'ForwardBindingItem').replace('ChatBubbleAccessoryForward', 'ForwardBindingAccessory').replace('AvatarControl', 'ForwardBindingAvatar')
    shake = declaration(source, '    public func shakeContentView(').replace('public func', 'func').replace('ChatRowItem', 'ForwardBindingItem').replace('ChatLayerRowView', host)
    layout_source = source[source.index('    public override func updateLayout(size:'):]
    placement = declaration(layout_source, '        if let view = forwardName {') if name == 'NativeForwardBindingRow' else next(line for line in source.splitlines() if '?.layoutForwardName(origin:' in line)
    background = next(line for line in source.splitlines() if 'forwardName?.backgroundColor =' in line or '?.forwardName?.layer.backgroundColor =' in line)
    if name == 'NativeForwardBindingRow':
        tooltip_method = 'func showHiddenForwardTooltip() { guard let forwardName else { return }; recordForwardTooltip(for: forwardName, text: "Hidden sender", autoCorner: false) }'
    else:
        tooltip_method = declaration(source, '    public func showHiddenForwardTooltip(').replace('public func', 'func').replace('tooltip(', 'recordForwardTooltip(').replace('strings().chatTooltipHiddenForwardName', '"Hidden sender"')
    forward_fixture += """
final class %s: View {
    let rowView: View
    let bubbleView = View()
    let contentView = View()
    let rightView = HostedRightStub()
    func moveHostedRightForShake() -> (() -> Void)? { nil }
    var statusControl: View?, forwardStatusControl: View?, replyView: View?, adminBadge: View?, adminBadgeBg: View?, boostBadge: View?, viaAccessory: View?
    var replyNode: ChatLayerControlNode?
    var captionViews: [SenderCaption] = []
    var item: Any?
    %s
    var forwardPhoto: ForwardBindingAvatar?
    var forwardAccessory: ForwardBindingAccessory?
    required init(frame: NSRect) {
        rowView = %s(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
        rowView.addSubview(bubbleView)
        rowView.addSubview(contentView)
        (rowView as? %s)?.layerHitBackground = bubbleView
    }
    required init?(coder: NSCoder) { fatalError() }
    func forwardNamePoint(_ item: ForwardBindingItem) -> NSPoint { NSPoint(x: 25, y: 20) }
    func forwardPhotoPoint(_ item: ForwardBindingItem) -> NSPoint { NSPoint(x: 39, y: 20) }
    func bubbleFrame(_ item: ForwardBindingItem) -> NSRect { NSRect(x: 10, y: 10, width: 270, height: 90) }
    func contentFrameModifier(_ item: ForwardBindingItem) -> NSRect { NSRect(x: 25, y: 70, width: 200, height: 20) }
    func bind(_ item: ForwardBindingItem, animated: Bool = false) {
        self.item = item
        bubbleView.frame = bubbleFrame(item)
        contentView.frame = contentFrameModifier(item)
        fillForward(item, animated: animated)
    }
    func layoutName(_ item: ForwardBindingItem, transition: ContainedViewLayoutTransition = .immediate) {
%s
    }
    func updateNameBackground(_ contentColor: NSColor) {
%s
    }
%s
%s
%s
}
""" % (name, property, host, host, placement, background, binding, shake, tooltip_method)
(output / 'ForwardBinding.swift').write_text(forward_fixture)

runpy.run_path(str(lab / "prepare-quote-scans.py"))

runpy.run_path(str(lab / "prepare-quote-masks.py"))

runpy.run_path(str(lab / "prepare-quote-icons.py"))

runpy.run_path(str(lab / "prepare-live-fold-baseline.py"))

with (folding_output / 'QuoteLayer.swift').open('a') as stream:
    stream.write('\npublic func sharedFoldingQuoteIconForLab() -> CGImage { quoteIcon }\n')
for module in ['FoldingViewHarness', 'FoldingViewHarnessBaseline']:
    path = lab / 'Sources' / module / 'Generated/Current.swift'
    contents = path.read_text()
    assert quote_icon.strip() in contents
    contents = contents.replace(quote_icon.strip(), 'private let quoteIcon: CGImage = InputTextView.sharedFoldingQuoteIconForLab()', 1)
    path.write_text('import InputTextView\n' + contents)
for module, name in [('InputTextView', 'QuoteWrapper.swift'), ('FoldingViewHarness', 'Legacy.swift'), ('FoldingViewHarnessBaseline', 'Legacy.swift')]:
    path = lab / 'Sources' / module / 'Generated' / name
    contents = path.read_text()
    assert quote_icon.strip() in contents
    if module == 'InputTextView':
        contents = contents.replace(quote_icon.strip(), 'private let quoteIcon: CGImage = sharedFoldingQuoteIconForLab()', 1)
    else:
        contents = 'import InputTextView\n' + contents.replace(quote_icon.strip(), 'private let quoteIcon: CGImage = InputTextView.sharedFoldingQuoteIconForLab()', 1)
    path.write_text(contents)

redraw_reference = lab / 'Reference/quote-redraw-original.swift.txt'
assert hashlib.sha256(redraw_reference.read_bytes()).hexdigest() == json.loads(redraw_reference.with_suffix('.json').read_text())['sha256']
with (folding_output / 'QuoteLayer.swift').open('a') as stream:
    stream.write('\n' + redraw_reference.read_text().replace('FoldingTextQuoteLayer', 'OriginalRedrawQuoteLayer'))

inline_emoji_sources = [root / 'packages/ChatUI/Sources/ChatUI' / name for name in ['ChatLayerInlineEmoji.swift', 'ChatLayerMessageTextView.swift', 'ChatLayerMessageText+Layout.swift', 'ChatMessageView.swift', 'ChatRowView.swift']]
inline_emoji_sources += [lab / path for path in ['Sources/TelegramContext/Context.swift', 'Sources/InputView/Emoji.swift', 'Sources/InlineStickerLayer/Media.swift', 'Sources/FoldingViewHarness/ChatTextDependencies.swift', 'Sources/FoldingViewHarness/CaptionDependencies.swift', 'Tests/FoldingViewTests/LiveInlineEmojiTests.swift', 'prepare.py', 'prepare-captions.py', 'Package.swift']]
(lab / 'inline-emoji-integration-provenance.json').write_text(json.dumps({'source_sha256': {str(source.relative_to(root)): hashlib.sha256(source.read_bytes()).hexdigest() for source in inline_emoji_sources}, 'scope': 'Exact production helper and host; extracted production body/caption methods; real TGUIKit; deterministic media/account stand-ins; no real decoding or asynchronous fetching'}, indent=2) + '\n')
