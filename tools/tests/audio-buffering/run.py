import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--list-source', type=Path, default=root / 'packages/AudioPlayerUI/Sources/AudioPlayerUI/PlayerListController.swift')
parser.add_argument('--inline-source', type=Path, default=root / 'packages/AudioPlayerUI/Sources/AudioPlayerUI/InlineAudioPlayerView.swift')
parser.add_argument('--core-source', type=Path, default=root / 'packages/AudioPlayerCore/Sources/AudioPlayerCore/AudioPlayerController.swift')
args = parser.parse_args()
listing, inline, core = [p.read_text() for p in [args.list_source, args.inline_source, args.core_source]]

def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]

view = listing[listing.index('final class PlayerListView'):]
fixture = Path(__file__).with_name('BufferingTests.swift').read_text()
for key, value in [
    ('__HELPER__', (root / 'packages/AudioPlayerUI/Sources/AudioPlayerUI/AudioPlayerBuffering.swift').read_text()),
    ('__LIST_BINDING__', section(view, '    deinit {', '    fileprivate func updateState(')),
    ('__LIST_SET__', section(view, '    func setController(', '    override func updateLocalizationAndTheme')),
    ('__LIST_DELEGATES__', view[view.index('    private func update(_ song:') if '    private func update(_ song:' in view else view.index('    func songDidChanged('):view.index('\n}\n\n\npublic class PlayerListController')]),
    ('__INLINE_STATUS__', section(inline, '    func updateStatus(', '    private var playProgressStyle:')),
    ('__CORE_BUFFER__', section(core, '    private let bufferingStatusValuePromise', '    fileprivate var timer:').replace('public private(set)', '')),
    ('__STOP__', section(core, '    public func stop() {', '    @discardableResult public func set(trackProgress:')),
    ('__LISTENERS__', section(core, '    public func add(listener:', '\n}\n\npublic class APChatController')),
]:
    fixture = fixture.replace(key, value.replace('public ', ''))
with tempfile.TemporaryDirectory(prefix='audio-buffering-') as directory:
    directory = Path(directory)
    dependencies = ', '.join('.package(path: ' + json.dumps(str(root / p)) + ')' for p in ['submodules/telegram-ios/submodules/SSignalKit', 'submodules/telegram-ios/submodules/Utils/RangeSet'])
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "AudioBuffering", platforms: [.macOS(.v10_13)], dependencies: [' + dependencies + '], targets: [.testTarget(name: "BufferingTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit"), .product(name: "RangeSet", package: "RangeSet")], path: "Tests")])\n')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BufferingTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
