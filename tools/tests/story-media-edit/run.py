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
start = source.index('public enum StoryUploadResult')
result = source[start:source.index('enum PendingStoryUploadInternalPhase', start)].replace('public ', '')
start = source.index('func _internal_editStory(')
edit = source[start:source.index('public enum EditStoryPrivacyError', start)]
fixture = Path(__file__).with_name('StoryMediaEditTests.swift').read_text().replace('__SOURCE__', result + edit)
with tempfile.TemporaryDirectory(prefix='story-media-edit-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryMediaEdit", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StoryMediaEditTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryMediaEditTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
