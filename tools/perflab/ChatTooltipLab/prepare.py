from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
item_path = root / 'packages/ChatUI/Sources/ChatUI/ChatRowItem.swift'
view_path = root / 'packages/ChatUI/Sources/ChatUI/ChatRightView.swift'
item = item_path.read_text()
view = view_path.read_text()
method = item[item.index('    func tooltipCountdownText()'):item.index('    public init(_ initialSize:NSSize, _ chatInteraction:', item.index('    func tooltipCountdownText()'))]
helpers = view[view.index('    private func bindTooltip('):view.index('    public override func mouseUp(with event:', view.index('    private func bindTooltip('))]
fields = view[view.index('    private weak var item:ChatRowItem?'):view.index('    public var isReversed:')]
assert 'bindTooltip(item)' in view[view.index('    public func set(item:ChatRowItem'):view.index('        guard let frames = item.rightFrames')]
assert 'updateTooltip' not in item and 'updateCountDownTimer' not in item and 'originalFullDate' not in item
reference = (lab / 'Reference.swift.txt').read_text()
output = 'import Cocoa\nimport TGUIKit\nimport SwiftSignalKit\n\n'
output += 'class ChatRowItem: ItemEnvironment {\n' + method + '}\n'
output += 'class CurrentTooltipView: ViewEnvironment {\n' + fields + '    func set(_ item: ChatRowItem) { bindTooltip(item) }\n' + helpers + '}\n'
output += reference
output = output.replace('SwiftSignalKit.Timer', 'LabTimer')
(lab / 'Sources/TooltipRows/Generated.swift').write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': '9c646ac2a', 'production_sha256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [item_path, view_path]}, 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest()}, indent=2) + '\n')
