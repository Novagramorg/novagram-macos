import argparse
import json
import re
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/PeerMediaUI/Sources/PeerMediaUI/SendAudioModalController.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('    let sharedAudioSignal =')
shared = source[start:source.index('    actionsDisposable.add((sharedAudioSignal', start)]
shared += '\nreturn sharedAudioSignal' + ('\n' if 'peerMediaSearchMessages' in shared else ' |> map { $0.0.messages }\n')
start = source.index('            let sharedSearch:')
search = source[start:source.index('            let botSearch:', start)] + '\nreturn sharedSearch\n'
start = source.index('                botSearch =')
end = re.search(r'^ {16}\|> map \{ (?:contextResult|results)', source[start:], re.M).start() + start
bot = source[start:end].replace('botSearch =', 'let botSearch =', 1)
bot += '\nreturn botSearch' + ('\n' if 'sendAudioBotSearchResults' in bot else ' |> map { $0?.results ?? [] }\n')
scroll = ''
if '    controller.didLoad = {' in source:
    start = source.index('    controller.didLoad = {')
    scroll = source[start:source.index('    var progressOverlay:', start)]
start = source.index('    controller.onDeinit = {')
close = source[start:source.index('    let modalController =', start)]
fixture = Path(__file__).with_name('AudioPaginationTests.swift').read_text()
for key, value in [('__SHARED__', shared), ('__SEARCH__', search), ('__BOT__', bot), ('__SCROLL__', scroll), ('__CLOSE__', close)]:
    fixture = fixture.replace(key, value)
with tempfile.TemporaryDirectory(prefix='send-audio-pagination-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AudioPagination", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "AudioPaginationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/AudioPaginationTests.swift').write_text(fixture)
    for name in ['PeerMediaSearchPagination.swift', 'SendAudioBotPagination.swift']:
        content = (root / 'packages/PeerMediaUI/Sources/PeerMediaUI' / name).read_text().replace('import TelegramCore\n', '').replace('import Postbox\n', '')
        (directory / 'Tests' / name).write_text(content)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
