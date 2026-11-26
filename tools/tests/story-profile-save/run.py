import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('public enum UpdateStoriesArePinnedError') if 'public enum UpdateStoriesArePinnedError' in source else source.index('func _internal_updateStoriesArePinned(')
source = source[start:source.index('public enum UpdatePinnedToTopStoriesError', start)].replace('public ', '')
fixture = Path(__file__).with_name('StoryProfileSaveTests.swift').read_text().replace('__SOURCE__', source)
with tempfile.TemporaryDirectory(prefix='story-profile-save-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryProfileSave", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StoryProfileSaveTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryProfileSaveTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
