from pathlib import Path
import hashlib
import json
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
row_path = 'packages/ChatListUI/Sources/ChatListUI/ChatListRowView.swift'
controller_path = 'packages/ChatListUI/Sources/ChatListUI/PeersListController.swift'
baseline = '590fd8894'

def method(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

def generated(name, source):
    visibility = source[source.index('             let unhideProgress = item.getHideProgress?()'):source.index('             contentView.change(pos: contentPoint(item)')]
    badge_start = next(line for line in source.splitlines() if 'if ' in line and 'item.ctxShortBadgeNode' in line)
    badge = source[source.index(badge_start):source.index('             if item.hasActiveGroupCall, badgeShortView == nil')]
    update = method(source, '    public func updateHideProgress(animated: Bool)')
    helper = method(source, '    private func updateContentVisibility(') if '    private func updateContentVisibility(' in source else ''
    tail = source[source.index('        contentView.needsLayout = true', source.index('    public override func set(item:TableRowItem')):source.index('    public func initRevealState()')]
    tail = tail[:tail.rfind('    }')]
    return f'''final class {name}: RowEnvironment {{
    override func set(item: TableRowItem, animated: Bool = false) {{
        super.set(item: item, animated: animated)
        guard let item = item as? ChatListRowItem else {{ return }}
{visibility}
{badge}
{tail}
    }}
{helper}
{update}
}}
'''

original = subprocess.check_output(['git', 'show', baseline+':'+row_path], cwd=root, text=True)
current = (root/row_path).read_text()
if '--baseline' in sys.argv:
    current = original
output = 'import Cocoa\nimport TGUIKit\n' + generated('ReferenceRow', original) + generated('CandidateRow', current)
controller = subprocess.check_output(['git', 'show', baseline+':'+controller_path], cwd=root, text=True) if '--baseline' in sys.argv else (root/controller_path).read_text()
for name, row, code in [('ReferenceController', 'ReferenceRow', subprocess.check_output(['git', 'show', baseline+':'+controller_path], cwd=root, text=True)), ('CandidateController', 'CandidateRow', controller)]:
    update = method(code, '    open override func updateSwipingState(_ state: SwipeState, controller: ViewController, isPrevious: Bool)').replace('open override', 'override').replace('ChatListRowView', row).replace('controller: ViewController', 'controller: ControllerTarget')
    progress = method(code, '    open func getSwipeProgress()').replace('open func', 'func')
    output += f'final class {name}: ControllerEnvironment {{\n{progress}\n{update}\n}}\n'
path = lab/'Sources/SwipeLab/Generated.swift'
path.write_text(output)
(lab/'generation.json').write_text(json.dumps({'baseline': baseline, 'row_sha256': hashlib.sha256(current.encode()).hexdigest(), 'controller_sha256': hashlib.sha256(controller.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2)+'\n')
