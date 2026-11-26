import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/SettingsUI/Sources/SettingsUI/BlockedPeersViewController.swift')
args = parser.parse_args()
source = args.source.read_text()
modern = 'private struct BlockedPeersEditingState' in source
if modern:
    state = source[source.index('private struct BlockedPeersEditingState'):source.index('private final class BlockedPeerControllerArguments')]
else:
    state = (root / 'packages/TelegramUtils/Sources/TelegramUtils/PeerListEditingState.swift').read_text().replace('import Postbox', '')
entries = source[source.index('private enum BlockedPeerEntryStableId'):source.index('    public func item(')] + '}\n'
entries += source[source.index('private func blockedPeersControllerEntries'):source.index('fileprivate func prepareTransition')]
start = source.index('    private let statePromise', source.index('open class BlockedPeersViewController'))
fields = source[start:source.index('    open override func viewDidLoad', start)]
if modern:
    methods = source[source.index('    private func removePeer('):source.index('    open override func update(with state:')]
    pending = 'stateValue.with { $0.removingPeerIds }'
else:
    start = source.index('        let updateState:')
    end = source.index('        }, openPeer:', start)
    action = source[start:end].replace('let arguments = BlockedPeerControllerArguments(context: context, removePeer:', 'let action: (PeerId) -> Void =')
    methods = 'func removePeer(_ peerId: PeerId) {\nlet context = self.context\n' + action + '\n}\naction(peerId)\n}\n'
    start = source.index('    deinit {', end)
    methods += source[start:source.index('    open override func update(with state:', start)]
    pending = 'stateValue.with { Set($0.removingPeerId.map { [$0] } ?? []) }'
fixture = Path(__file__).with_name('BlockedPeersUITests.swift').read_text()
merge = (root / 'packages/TGUIKit/Sources/MergeLists.swift').read_text()
fixture = fixture.replace('__MERGE__', merge[:merge.index('public func mergeListsStableWithUpdatesReversed')])
fixture = fixture.replace('__PRODUCTION__', (state + entries).replace('private ', ''))
fixture = fixture.replace('__FIELDS__', fields.replace('private ', '')).replace('__METHODS__', methods.replace('private ', ''))
fixture = fixture.replace('__PENDING__', pending)
fixture = fixture.replace('__STATE__', 'BlockedPeersEditingState' if modern else 'PeerListEditingState')
with tempfile.TemporaryDirectory(prefix='blocked-peers-ui-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BlockedPeersUI", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BlockedPeersUITests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BlockedPeersUITests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
