from pathlib import Path
import hashlib
import json
import re
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = root / 'packages/ShortPeerRow/Sources/ShortPeerRow/ChatActivitiesModel.swift'
source = path.read_text()
model_start = 'public class ChatActivitiesModel:'
view = source[source.index('public enum ChatActivityAnimation'):source.index(model_start)]
current = source[source.index(model_start):]
geometry_path = root / 'packages/TelegramTheme/Sources/TelegramTheme/ThumbUtils.swift'
geometry = geometry_path.read_text()
geometry = geometry[geometry.index('fileprivate let minDiameter:'):geometry.index('private func generateUploadFileAnimatedImage')]
theme_path = root / 'packages/TelegramTheme/Sources/TelegramTheme/TelegramPresentationTheme.swift'
theme = theme_path.read_text()
theme = theme[theme.index('public struct ActivitiesTheme'):theme.index('public final class TelegramTabBarTheme')]
activity_path = root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/State/PeerInputActivity.swift'
activity = activity_path.read_text()
activity = activity[activity.index('public enum PeerInputActivity:'):activity.index('extension PeerInputActivity {')]
output = 'import AppKit\nimport TGUIKit\nimport SwiftSignalKit\n' + theme + geometry + activity + view
output += current.replace('ChatActivitiesModel', 'MeasuredActivitiesModel')
output += '\nstruct LabStrings {\n'
for name in sorted(set(re.findall(r'strings\(\)\.([A-Za-z0-9_]+)', current))):
    if 'Multi' in name:
        args, values = '_ name: String, _ count: Int', '[name, String(count)]'
    elif name == 'peerActivityChatEnjoyingAnimations':
        args, values = '_ name: String, _ emoji: String', '[name, emoji]'
    elif 'Chat' in name or name == 'peerActivityUserEnjoyingAnimations':
        args, values = '_ value: String', '[value]'
    else:
        output += f'    var {name}: String {{ localize("{name}", []) }}\n'
        continue
    output += f'    func {name}({args}) -> String {{ localize("{name}", {values}) }}\n'
output += '}\nfunc strings() -> LabStrings { LabStrings() }\n'
row_path = root / 'packages/ChatListUI/Sources/ChatListUI/ChatListRowView.swift'
row_source = row_path.read_text()
def observer(text):
    start = text.index('    public var inputActivities:')
    return text[start:text.index('    public override func onShowContextMenu()', start)]
reference = (lab / 'Reference.swift.txt').read_text()
assert reference == observer(subprocess.check_output(['git', 'show', 'f3bcad0ca:packages/ChatListUI/Sources/ChatListUI/ChatListRowView.swift'], cwd=root).decode())
peer_equality = (root / 'packages/TelegramUtils/Sources/TelegramUtils/PeerEquatable.swift').read_text()
peer_equality = peer_equality[peer_equality.index('public struct PeerEquatable:'):peer_equality.index('public struct CachedDataEquatable:')]
output += peer_equality
layout_field = next(line for line in row_source.splitlines() if 'private var activityLayout:' in line) + '\n'
for name, body, fields in [('CurrentRow', observer(row_source), layout_field), ('ReferenceRow', reference, '')]:
    output += 'final class ' + name + ': RowEnvironment {\n' + fields + body + '\n}\n'
target = lab / 'Sources/ActivityText/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': 'f3bcad0ca', 'row_sha256': hashlib.sha256(row_source.encode()).hexdigest(), 'model_sha256': hashlib.sha256(source.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
