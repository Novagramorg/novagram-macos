from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
item_path = 'packages/ShortPeerRow/Sources/ShortPeerRow/ShortPeerRowItem.swift'
view_path = 'packages/ShortPeerRow/Sources/ShortPeerRow/ShortPeerRowView.swift'
item = (root / item_path).read_text()
view = (root / view_path).read_text()
prepare = item[item.index('    open override func prepare(_ selected:Bool)'):item.index('    open var ctxMonoforumMessages:')].replace('open override func', 'func')
fields = item[item.index('    private var textLayoutWidths:'):item.index('    private var titleAttr:')]
reference = (lab / 'ReferencePrepare.swift.txt').read_text().replace('open override func', 'func')
observer = view[view.index('    private func updateInteractionObserver()'):view.rindex('}')]
assert 'private weak var observedInteraction: SelectPeerInteraction?' in view
set_body = view[view.index('    open override func set(item:'):view.index('    public func accessibilityPressContextLabel()')]
assert set_body.count('updateInteractionObserver()') == 1
assert 'interaction.add(observer:' not in set_body
assert 'interaction.remove(observer:' not in set_body
assert 'viewDidMoveToSuperview()' not in set_body
selected_properties = item[item.index('    private var selectedTitleLayout:'):item.index('    public let leftImage:')].replace('public var ', 'override var ')
eager_properties = """
    private var eagerTitleLayout: (TextNodeLayout, TextNode)?
    private var eagerStatusLayout: (TextNodeLayout, TextNode)?
    override var titleSelected: (TextNodeLayout, TextNode)? {
        get { eagerTitleLayout }
        set { eagerTitleLayout = newValue }
    }
    override var statusSelected: (TextNodeLayout, TextNode)? {
        get { eagerStatusLayout }
        set { eagerStatusLayout = newValue }
    }
"""
eager_source = subprocess.check_output(['git', 'show', 'd0610bf3d:' + item_path], cwd=root, text=True)
eager_block = eager_source[eager_source.index('    open override func prepare(_ selected:Bool)'):eager_source.index('    open var ctxMonoforumMessages:')]
assert (lab / 'ReferenceEagerPrepare.swift.txt').read_text() == eager_block
eager_reference = eager_block.replace('open override func', 'func')
output = 'import Cocoa\nimport TGUIKit\n\nclass ShortPeerRowItem: ItemEnvironment {\n' + fields + selected_properties + prepare + '}\n\nclass ReferenceRowItem: ItemEnvironment {\n' + eager_properties + reference + '}\n'
output += '\nclass EagerRowItem: ItemEnvironment {\n' + fields + eager_properties + eager_reference + '}\n'
output += '''
class RowObserverView: NSView, Notifable {
    private weak var observedInteraction: SelectPeerInteraction?
    var item: AnyObject? { didSet { updateInteractionObserver() } }
    var received: [Int] = []
    func notify(with value: Any, oldValue: Any, animated: Bool) { received.append(value as! Int) }
    func isEqual(to other: Notifable) -> Bool { self === other }
'''
output += observer + '}\n'
(lab / 'Sources/PeerRows/Generated.swift').write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline_commit': 'b6516131e', 'production_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in [item_path, view_path]}, 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')

accessory_reference = (lab / 'ReferenceAccessories.swift.txt').read_text()
accessory_start = view.index('        if case .selectable(true) = item.type {', view.index('    open override func set(item:'))
accessory_end = view.index('        switch item.interactionType {', accessory_start)
accessory_body = view[accessory_start:accessory_end]
accessory_body += view[view.index('        if !item.rightActions.actions.isEmpty {', accessory_end):view.index('        if let displayLayout = item.ctxMonoforumMessages {', accessory_end)]
helper = view[view.index('    private func updateContextLabel('):view.index('    open override func set(item:')]
style = next(line for line in view.splitlines() if 'private var choiceImageStyle:' in line)
accessories = 'import Cocoa\nimport TGUIKit\n\n'
for name, body, methods in [('CurrentAccessoryView', accessory_body, style + '\n' + helper), ('ReferenceAccessoryView', accessory_reference, '')]:
    accessories += 'class ' + name + ': AccessoryEnvironment {\n' + methods + '\n    override func bind(_ item: AccessoryItem, animated: Bool = false) {\n' + body + '    }\n}\n'
(lab / 'Sources/PeerRows/GeneratedAccessories.swift').write_text(accessories)
(lab / 'accessory-provenance.json').write_text(json.dumps({'baseline_commit': '7b573a350', 'production_sha256': hashlib.sha256(view.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(accessory_reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(accessories.encode()).hexdigest()}, indent=2) + '\n')

badge_path = 'packages/ShortPeerRow/Sources/ShortPeerRow/SendPaidMessageBadge.swift'
badge = (root / badge_path).read_text()
badge_reference = (lab / 'ReferencePaidBadge.swift.txt').read_text()
badge_method = view[view.index('    private func updatePresentation('):view.index('    open func isEqual(to other:')]
reference_method, reference_draw = badge_reference.split('public func generalSendPaidMessage', 1)
badge_output = 'import Cocoa\nimport TGUIKit\n\n' + badge[badge.index('final class SendPaidMessageBadgeCache'):]
badge_output += '\npublic func referenceGeneralSendPaidMessage' + reference_draw
for name, body in [('CurrentPaidBadgeView', badge_method), ('ReferencePaidBadgeView', reference_method.replace('generalSendPaidMessage(', 'referenceGeneralSendPaidMessage('))]:
    badge_output += '\nclass ' + name + ': PaidBadgeEnvironment {\n' + body.replace('private func updatePresentation(', 'override func bind(') + '}\n'
assert view.count('self.photoBadge = nil\n                self.paidMessageBadgeCache = nil') == 1
assert view.count('self.photoBadge = nil\n            self.paidMessageBadgeCache = nil') == 1
(lab / 'Sources/PeerRows/GeneratedPaidBadge.swift').write_text(badge_output)
(lab / 'paid-badge-provenance.json').write_text(json.dumps({'baseline_commit': '007289e39', 'production_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in [view_path, badge_path]}, 'reference_sha256': hashlib.sha256(badge_reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(badge_output.encode()).hexdigest()}, indent=2) + '\n')

(lab / 'selection-provenance.json').write_text(json.dumps({'baseline_commit': 'd0610bf3d', 'production_sha256': hashlib.sha256(item.encode()).hexdigest(), 'reference_sha256': hashlib.sha256((lab / 'ReferenceEagerPrepare.swift.txt').read_bytes()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
