from pathlib import Path

lab = Path(__file__).resolve().parent
root = lab.parents[2]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatRightView.swift').read_text()
source = source[source.index('final class ChatRightTextLayer:'):source.index('public class ChatRightView:')]
(lab / 'Sources/StatusLayers/Generated.swift').write_text('import Cocoa\nimport TGUIKit\n\n' + source)
