import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]

def read(name):
    path = 'packages/ChatUI/Sources/ChatUI/' + name + '.swift'
    return subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:' + path], text=True) if args.baseline else (root / path).read_text()

def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

manager = read('ChatMessageThrottledProcessingManager')
effects = read('EmojiScreenEffect')
parts = {
    '__PROCESSING_MANAGER__': section(manager, 'public final class ChatMessageThrottledProcessingManager', 'public final class ChatMessageVisibleThrottledProcessingManager'),
    '__REMOVE_EFFECTS__': section(effects, '    func removeAll()', '    private func initAnimation('),
    '__DISPOSE_EFFECT__': section(effects, '    private func deinitAnimation(', '    func removeAll()'),
    '__EFFECT_DISPOSABLES__': section(effects, '    private let dataDisposable:', '    private let limit:') if '    private let dataDisposable:' in effects else section(effects, '    private var dataDisposable:', '    private let limit:'),
}
with tempfile.TemporaryDirectory(prefix='chat-lifecycle-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatLifecycle", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatLifecycleTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    for path in Path(__file__).parent.glob('*Tests.swift'):
        fixture = path.read_text()
        for name, body in parts.items():
            fixture = fixture.replace(name, body)
        (directory / 'Tests' / path.name).write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
