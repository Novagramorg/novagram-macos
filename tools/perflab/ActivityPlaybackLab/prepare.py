from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = root / 'packages/ShortPeerRow/Sources/ShortPeerRow/ChatActivitiesModel.swift'
source = path.read_text()
start = 'public enum ChatActivityAnimation'
end = 'public class ChatActivitiesModel:'
current = source[source.index(start):source.index(end)]
old = subprocess.check_output(['git', 'show', '4ae6313e0:packages/ShortPeerRow/Sources/ShortPeerRow/ChatActivitiesModel.swift'], cwd=root).decode()
reference = (lab / 'Reference.swift.txt').read_text()
assert old[old.index(start):old.index(end)] == reference
assert 'activityView.stopAnimation()' in source[source.index('    public func clean()'):]
geometry_path = root / 'packages/TelegramTheme/Sources/TelegramTheme/ThumbUtils.swift'
geometry = geometry_path.read_text()
geometry = geometry[geometry.index('fileprivate let minDiameter:'):geometry.index('private func generateUploadFileAnimatedImage')]
theme_path = root / 'packages/TelegramTheme/Sources/TelegramTheme/TelegramPresentationTheme.swift'
theme = theme_path.read_text()
theme = theme[theme.index('public struct ActivitiesTheme'):theme.index('public final class TelegramTabBarTheme')]
output = 'import AppKit\nimport TGUIKit\n' + theme + geometry
for prefix, body in [('Current', current), ('Reference', reference)]:
    for name in ['ChatActivityAnimation', 'ChatActivityIndicatorLayer', 'ChatActivitiesView']:
        body = body.replace(name, prefix + name)
    output += body
target = lab / 'Sources/Activity/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': '4ae6313e0', 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'geometry_sha256': hashlib.sha256(geometry_path.read_bytes()).hexdigest(), 'theme_sha256': hashlib.sha256(theme_path.read_bytes()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
