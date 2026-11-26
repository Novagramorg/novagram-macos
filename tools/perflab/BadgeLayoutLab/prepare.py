from pathlib import Path
import hashlib
import json
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
base = '4536e7fd6'
item_path = 'packages/ChatListUI/Sources/ChatListUI/ChatListRowItem.swift'
view_path = 'packages/ChatListUI/Sources/ChatListUI/ChatListRowView.swift'

def block(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    end = brace + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

def generate(name, source):
    archive = block(source, '        if mutedCount > 0  {')
    normal = block(source, '        if showBadge, !chatListGramBadgeHidesUnreadCounter')
    getters = block(source, '    public var ctxBadgeNode:BadgeNode?') + '\n' + block(source, '    public var ctxShortBadgeNode:BadgeNode?')
    return f'''final class {name}: ItemEnvironment {{
    func setupArchive(_ mutedCount: Int) {{
{archive}
    }}
    func setupNormal(_ readState: ReadState?, isMuted: Bool = false, isUnreadMarked: Bool = false, mentionsCount: Int? = nil, showBadge: Bool = true, hasGramBadge: Bool = false) {{
{normal}
    }}
{getters}
}}
'''

old_item = subprocess.check_output(['git', 'show', base+':'+item_path], cwd=root, text=True)
old_view = subprocess.check_output(['git', 'show', base+':'+view_path], cwd=root, text=True)
item = old_item if '--baseline' in sys.argv else (root/item_path).read_text()
view = old_view if '--baseline' in sys.argv else (root/view_path).read_text()
output = 'import Cocoa\nimport TGUIKit\n' + block(item, 'func chatListGramBadgeHidesUnreadCounter(').replace('Int32?', 'Int?') + '\n' + generate('ReferenceItem', old_item) + generate('CandidateItem', item)
for name, source in [('referenceGate', old_view), ('candidateGate', view)]:
    gate = next(line.strip() for line in source.splitlines() if 'if ' in line and 'item.ctxShortBadgeNode' in line)
    output += f'func {name}(_ item: GateItem) -> Bool {{\n    {gate}\n        return badgeNode.size.width > 0\n    }}\n    return false\n}}\n'
(lab/'Sources/BadgeLab/Generated.swift').write_text(output)
(lab/'generation.json').write_text(json.dumps({'baseline': base, 'item_sha256': hashlib.sha256(item.encode()).hexdigest(), 'view_sha256': hashlib.sha256(view.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2)+'\n')
