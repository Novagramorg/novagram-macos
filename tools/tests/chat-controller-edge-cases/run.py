import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
source = (args.source or root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()

def section(start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

parts = {
    '__THREAD_SETUP__': section('        chatInteraction.updateChatLocationThread =', '        chatInteraction.reportSpamAndClose ='),
    '__PHOTO_SETUP__': section('        chatInteraction.editEditingMessagePhoto =', '        chatInteraction.requestMessageActionCallback ='),
    '__MEDIA_SETUP__': section('        chatInteraction.updateEditingMessageMedia =', '        chatInteraction.addContact ='),
}
drag_start = source.index('    public override func draggingItems(for pasteboard:')
file_start = source.index('                if list.count == 1, let editState =', drag_start)
file_end = source.index('                if !list.isEmpty {', file_start)
image_start = source.index('                if let editState =', file_end)
image_end = source.index('                var items:[DragItem] = []', image_start)
parts['__FILE_DROP__'] = source[file_start:file_end]
parts['__IMAGE_DROP__'] = source[image_start:image_end]
parts['__EDIT_SESSION_UPDATE__'] = section('            if value.interfaceState.editState?.message.id != oldValue.interfaceState.editState?.message.id {', '            let context = self.context') if '            if value.interfaceState.editState?.message.id != oldValue.interfaceState.editState?.message.id {' in source else ''
parts['__SELECTION_UPDATE__'] = section('            if value.selectionState != oldValue.selectionState {', '                if value.selectionState != nil {') + '\n            }'
cleanup = section('    private func cleanup()', '    public override func readyToDetach()')
parts['__CLEANUP__'] = '\n'.join(line for line in cleanup.splitlines() if any(name + '.dispose()' in line for name in ['updateChatLocationThreadDisposable', 'editCurrentMessagePhotoDisposable', 'updateMediaDisposable', 'loadSelectionMessagesDisposable']))
with tempfile.TemporaryDirectory(prefix='chat-controller-edges-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatControllerEdges", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatControllerEdgeTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    for path in Path(__file__).parent.glob('*Tests.swift'):
        fixture = path.read_text()
        for name, body in parts.items():
            fixture = fixture.replace(name, body)
        (directory / 'Tests' / path.name).write_text(fixture)
    print('Testing ChatController from ' + str(args.source or 'working tree'), flush=True)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
