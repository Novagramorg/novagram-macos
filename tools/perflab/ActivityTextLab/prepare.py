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
current = source[source.index(model_start):].replace('private func activityTextLayout(', 'func activityTextLayout(')
old = subprocess.check_output(['git', 'show', 'd3f4a6235:packages/ShortPeerRow/Sources/ShortPeerRow/ChatActivitiesModel.swift'], cwd=root).decode()
reference = (lab / 'Reference.swift.txt').read_text()
assert old[old.index(model_start):] == reference
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
output += current.replace('ChatActivitiesModel', 'CurrentModel') + reference.replace('ChatActivitiesModel', 'ReferenceModel')
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
target = lab / 'Sources/ActivityText/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': 'd3f4a6235', 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'geometry_sha256': hashlib.sha256(geometry_path.read_bytes()).hexdigest(), 'theme_sha256': hashlib.sha256(theme_path.read_bytes()).hexdigest(), 'activity_enum_sha256': hashlib.sha256(activity.encode()).hexdigest()}, indent=2) + '\n')
