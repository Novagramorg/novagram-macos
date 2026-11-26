import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryPrivacyModalController.swift')
args = parser.parse_args()
source = args.source.read_text()
modern = 'let initialPrivacySignal =' in source
start = source.index('    let initialPrivacySignal =') if modern else source.index('    switch reason {\n    case .share, .upload:', source.index('    let updateState:'))
initial = source[start:source.index('    var peerIds', start)]
fields = source[source.index('    var peerIds', start):source.index('    let selectPeers:', start)]
select_start = source.index('    let selectPeers:')
start = source.index('    actionsDisposable.add(', select_start)
select = source[select_start:start]
disappear = ''
if '    controller.willDisappear =' in source:
    disappear_start = source.index('    controller.willDisappear =')
    disappear = source[disappear_start:source.index('    controller.validateData =', disappear_start)]
observer = source[start:source.index('    let adminedChannelsWithParticipants', start)]
start = source.index('    }, updateBlockList: {') + len('    }, updateBlockList: {')
block = source[start:source.index('    }, showEmojis:', start)]
helper = ''
if modern:
    helper = source[source.index('private func storyPrivacyBlockedPeerIds'):source.index('public func StoryPrivacyModalController<')]
combined_start = source.index('    actionsDisposable.add((combineLatest(adminedChannelsWithParticipants, blockedContext.state,')
combined = source[combined_start:source.index('    let textInteractions =', combined_start)]
privacy = (root / 'packages/StoriesUI/Sources/StoriesUI/StoryPosterState.swift').read_text()
privacy = privacy[privacy.index('public struct StoryPosterResultPrivacy'):privacy.index('public final class StoryPosterState')].replace('public ', '')
start = source.index('    let signal = statePromise.get() |> filter')
gate = source[start:source.index(' |> deliverOnMainQueue', start)].split(' |> filter ')[1]
fixture = Path(__file__).with_name('StoryPrivacyTests.swift').read_text()
for key, value in [('__PRIVACY__', privacy), ('__HELPER__', helper), ('__INITIAL__', initial), ('__FIELDS__', fields), ('__OBSERVER__', observer), ('__BLOCK__', block), ('__GATE__', gate), ('__SELECT__', select), ('__DISAPPEAR__', disappear), ('__COMBINED__', combined)]:
    fixture = fixture.replace(key, value)
with tempfile.TemporaryDirectory(prefix='story-privacy-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryPrivacy", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StoryPrivacyTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryPrivacyTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
