import argparse
import json
import re
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--source', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
def read_source(path):
    return subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:' + path], text=True) if args.baseline else (root / path).read_text()

controller = args.source.read_text() if args.source else read_source('packages/ChatUI/Sources/ChatUI/ChatController.swift')
clip = read_source('packages/TGUIKit/Sources/TGClipView.swift')

def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

parts = {
    '__DATE_SETUP__': section(controller, '        chatInteraction.jumpToDate =', '        let editMessage:'),
    '__FIRST_SETUP__': section(controller, '        chatInteraction.scrollToTheFirst =', '        chatInteraction.openFocusedMedia ='),
    '__MENTION_SETUP__': section(controller, '        chatInteraction.mentionPressed =', '        chatInteraction.clearMentions ='),
    '__REACTION_SETUP__': section(controller, '        chatInteraction.reactionPressed =', '        chatInteraction.editEditingMessagePhoto ='),
    '__FOCUS_SETUP__': section(controller, '        chatInteraction.focusMessageId =', '        chatInteraction.vote ='),
    '__CLIP_SCROLL__': section(clip, '    public func scroll(to point: NSPoint, animated:', '    func cancelScrolling()'),
    '__CLIP_UPDATE__': section(clip, '    public func updateBounds(to point:', '    private(set) var point:'),
}
processing = read_source('packages/ChatUI/Sources/ChatUI/ChatMessageThrottledProcessingManager.swift')
parts['__PROCESSING_MANAGER__'] = section(processing, 'public final class ChatMessageThrottledProcessingManager', 'public final class ChatMessageVisibleThrottledProcessingManager')
parts['__REACTIONS_MANAGER_INIT__'] = re.search(r'private let messageReactionsMentionProcessingManager = (.*)', controller).group(1)
parts['__UNREAD_PROCESSING__'] = section(controller, '        self.messageMentionProcessingManager.process =', '        self.refreshStoriesProcessingManager.process =')
parts['__VISIBLE_READ_IDS__'] = section(controller, '    private func visibleMessageIdsForReading(', '    private func canInteractiveRead()') if '    private func visibleMessageIdsForReading(' in controller else ''
parts['__CANCEL_FOCUS__'] = section(controller, '    private func cancelMessageFocus()', '    public func clearReplyStack()') if '    private func cancelMessageFocus()' in controller else '    func cancelMessageFocus() { messageIndexDisposable.set(nil) }'
with tempfile.TemporaryDirectory(prefix='chat-message-focus-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatMessageFocus", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatMessageFocusTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    for path in Path(__file__).parent.glob('*Tests.swift'):
        fixture = path.read_text()
        for name, body in parts.items():
            fixture = fixture.replace(name, body)
        (directory / 'Tests' / path.name).write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
