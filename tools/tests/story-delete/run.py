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
start = source.index('public enum DeleteStoriesError') if 'public enum DeleteStoriesError' in source else source.index('func _internal_deleteStories(')
source = source[start:source.index('func _internal_markStoryAsSeen(', start)].replace('public ', '')
fixture = Path(__file__).with_name('StoryDeleteTests.swift').read_text().replace('__SOURCE__', source)
cache_source = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/StoryListContext.swift').read_text()
def block(marker):
    start = cache_source.index(marker); brace = cache_source.index('{', start); end = brace + 1; depth = 1
    while depth:
        depth += (cache_source[end] == '{') - (cache_source[end] == '}'); end += 1
    return cache_source[start:end]
fixture = fixture.replace('__CACHE_HELPERS__', '\n'.join(block(marker) for marker in ['private func _internal_visitStoryListCaches(', 'func _internal_removeStoriesFromListCaches(', 'func _internal_removeStoryFromListCaches(']))

with tempfile.TemporaryDirectory(prefix='story-delete-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryDelete", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StoryDeleteTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryDeleteTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
