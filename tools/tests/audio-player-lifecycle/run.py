import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/AudioPlayerUI/Sources/AudioPlayerUI/InlineAudioPlayerView.swift')
parser.add_argument('--core-source', type=Path, default=root / 'packages/AudioPlayerCore/Sources/AudioPlayerCore/AudioPlayerController.swift')
args = parser.parse_args()
source = args.source.read_text()
core = args.core_source.read_text()

def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]

fixture = Path(__file__).with_name('LifecycleTests.swift').read_text()
for key, value in [
    ('__UPDATE__', section(source, '    public override func update(with', '    public override func viewDidMoveToWindow()')),
    ('__GUARD__', section(source, '    private func update(_ song:', '        let iconColor')),
    ('__DELEGATES__', section(source, '    public func songDidChanged(', '    private var progressHoverRect:')),
    ('__STOP__', section(source, '    func stopAndHide(', '    public required init(frame')),
    ('__LISTENERS__', section(core, '    public func add(listener:', '\n}\n\npublic class APChatController')),
]:
    fixture = fixture.replace(key, value.replace('public ', ''))
with tempfile.TemporaryDirectory(prefix='audio-player-lifecycle-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AudioLifecycle", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "LifecycleTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/LifecycleTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
