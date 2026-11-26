from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
lab = root / 'tools/perflab/ReactionPassiveLayerLab'
old_path = lab / 'Reference/ChatReactionsView.swift.txt'
new_path = root / 'packages/ChatUI/Sources/ChatUI/ChatReactionsView.swift'
helper_path = root / 'packages/ChatUI/Sources/ChatUI/ChatReactionTextLayer.swift'
old, new = old_path.read_text(), new_path.read_text()
assert hashlib.sha256(old_path.read_bytes()).hexdigest() == json.loads((lab / 'Reference/provenance.json').read_text())['sha256']

def block(text, needle):
    start = text.index(needle)
    pos = text.index('{', start)
    level = 1
    end = pos + 1
    while level:
        if text[end] == '{': level += 1
        elif text[end] == '}': level -= 1
        end += 1
    return text[start:end]

header = '''import Cocoa
import TGUIKit

struct LabReaction {
    enum Kind { case builtin; case custom }
    struct Value { var isSelected: Bool; var value: Kind }
    struct Presentation {
        var insetOuter: CGFloat = 10
        var insetInner: CGFloat = 5
        var reactionSize = CGSize(width: 16, height: 16)
        var avatarSize = CGSize(width: 20, height: 20)
        var selectedColor = NSColor.red.withAlphaComponent(0.4)
        var tagBackground: NSImage?
    }
    var text: TextViewLayout?
    var value: Value
    var presentation = Presentation()
}

class ReactionFixture: Control {
    let imageView = View(frame: CGRect(x: 10, y: 8, width: 16, height: 16))
    var reaction: LabReaction?
    var presses = 0
    required init(frame: CGRect) {
        super.init(frame: frame)
        layer?.masksToBounds = false
        imageView.isEventLess = true
        imageView.backgroundColor = .green
        addSubview(imageView)
        set(handler: { [weak self] _ in self?.presses += 1 }, for: .Click)
    }
    required init?(coder: NSCoder) { fatalError() }
    func bind(_ reaction: LabReaction, animated: Bool) { fatalError() }
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) { fatalError() }
    func ensureAvatars(_ inserted: [Int]) {}
    var textObject: AnyObject? { nil }
    var textFrame: CGRect? { nil }
    var nativeText: TextView? { nil }
    var countLayer: CALayer? { nil }
    var countAccessibility: NSAccessibilityElement? { nil }
    var selectionLayer: CALayer? { nil }
    var avatarHost: View? { nil }
    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
}
'''
parts = [header]
records = []
for source, candidate in [(old, False), (new, True)]:
    for tag in [False, True]:
        class_name = 'TagReactionView' if tag else 'ReactionView'
        body = block(source, 'public final class ' + class_name + ':')
        update = block(body, 'public func update(with reaction:')
        count_start = update.index('            if let text = reaction.text')
        count_end = update.index('            self.backgroundLayer?.image' if candidate else '            self.backgroundView?.image', count_start) if tag else update.index('            let (removed, inserted, updated)', count_start)
        count = update[count_start:count_end]
        selected_start = update.index('            if selectedUpdated')
        selected_end = update.index('            let presentation', selected_start) if tag else update.index('            if case .stars', selected_start)
        selected = update[selected_start:selected_end]
        layout = block(body, 'public func updateLayout(size:').replace('public func updateLayout', 'override func updateLayout')
        name = ('Current' if candidate else 'Original') + ('Tag' if tag else 'Full')
        text_name = 'textLayer' if candidate else 'textView'
        bg_name = 'backgroundLayer' if candidate else 'backgroundView'
        bg_type = ('ChatReactionTagBackgroundLayer' if tag else 'SimpleLayer') if candidate else ('NinePathImage' if tag else 'View')
        declarations = f'    var {text_name}: {"ChatReactionTextLayer" if candidate else "TextView"}?\n    var {bg_name}: {bg_type}?\n'
        if not tag:
            declarations += '    var avatarsContainer: View?\n' if candidate else '    let avatarsContainer = View(frame: NSMakeRect(0, 0, 24 * 3, 24))\n'
        setup = '' if candidate or tag else '        addSubview(avatarsContainer)\n        avatarsContainer.isEventLess = true\n'
        bind = '    override func bind(_ reaction: LabReaction, animated: Bool) {\n        let selectedUpdated = self.reaction?.value.isSelected != reaction.value.isSelected\n        self.reaction = reaction\n        let presentation = reaction.presentation\n'
        if tag:
            bind += selected + '\n' + count + '\n        self.' + bg_name + '?.image = reaction.presentation.tagBackground\n'
        else:
            bind += count + '\n' + selected + '\n'
        bind += '        updateLayout(size: frame.size, transition: .immediate)\n    }\n'
        methods = ''
        if candidate:
            for method in ['public override func accessibilityChildren()', 'public override func accessibilityHitTest(', 'public override func viewDidChangeBackingProperties()']:
                methods += block(body, method).replace('public override', 'override') + '\n'
            methods += '    override var countAccessibility: NSAccessibilityElement? { textLayer?.accessibleChild() }\n'
        else:
            methods += '    override var nativeText: TextView? { textView }\n'
        if candidate and not tag:
            lazy = block(body, 'if !inserted.isEmpty, avatarsContainer == nil')
            methods += '    override func ensureAvatars(_ inserted: [Int]) {\n' + lazy + '\n    }\n'
        layer = text_name if candidate else 'textView?.layer'
        selection = bg_name if candidate else bg_name + '?.layer'
        methods += f'    override var textObject: AnyObject? {{ {text_name} }}\n    override var textFrame: CGRect? {{ {text_name}?.frame }}\n    override var countLayer: CALayer? {{ {layer} }}\n    override var selectionLayer: CALayer? {{ {selection} }}\n'
        if not tag: methods += '    override var avatarHost: View? { avatarsContainer }\n'
        generated = 'final class ' + name + ': ReactionFixture {\n' + declarations + '    required init(frame: CGRect) {\n        super.init(frame: frame)\n' + setup + '    }\n    required init?(coder: NSCoder) { fatalError() }\n' + bind + layout + '\n' + methods + '}\n'
        parts.append(generated)
        records.append({'name': name, 'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'count_binding_sha256': hashlib.sha256(count.encode()).hexdigest(), 'background_binding_sha256': hashlib.sha256(selected.encode()).hexdigest(), 'layout_sha256': hashlib.sha256(layout.encode()).hexdigest()})
folder = output / 'Sources/ReactionHarness'
folder.mkdir(parents=True, exist_ok=True)
(folder / 'Generated.swift').write_text('\n'.join(parts))
(folder / helper_path.name).write_bytes(helper_path.read_bytes())
(output / 'binding-provenance.json').write_text(json.dumps({'extracted_bindings': records, 'helper_sha256': hashlib.sha256(helper_path.read_bytes()).hexdigest(), 'scope': 'Exact production passive text/background/geometry/AX methods. Icon is a plain eventless View; avatar insertion, media, effect players, account data and real reaction actions are outside fixture.'}, indent=2) + '\n')
