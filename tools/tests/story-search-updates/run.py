import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/StoryListContext.swift')
args = parser.parse_args()
source = args.source.read_text()
def block(text, marker, offset=0):
    start = text.index(marker, offset); end = text.index('{', start) + 1; depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}'); end += 1
    return text[start:end]
fixture = Path(__file__).with_name('StorySearchUpdatesTests.swift').read_text()
context = block(source, 'private final class Impl {', source.index('public final class SearchStoryListContext:'))
context = context.replace('private ', '').replace('final class Impl {', 'final class SearchContext {\n    typealias State = StoryListContextState', 1)
fixture = fixture.replace('__CONTEXT__', context)
helpers = [block(source, marker) for marker in ['private func _internal_storyEntityFileIds(', 'private func _internal_storyEntityFiles(', 'private func _internal_prunedStoryEntityFiles(', 'private func _internal_engineStoryWithViews(', 'private func _internal_engineStoryWithReaction(', 'private func _internal_mappedStoryViews(']]
fixture = fixture.replace('__HELPERS__', '\n'.join(helpers))
stories = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift').read_text()
fixture = fixture.replace('__REACTION_REDUCER__', block(stories, 'func _internal_updateStoryViewsForMyReaction(')).replace('__VIEWS_EMPTY__', block(stories, 'public var isEmpty: Bool {').replace('public ', ''))
with tempfile.TemporaryDirectory(prefix='story-search-updates-') as directory:
    path = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (path / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "StorySearchUpdates", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + ')], targets: [.testTarget(name: "StorySearchUpdatesTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (path / 'Tests').mkdir(); (path / 'Tests/StorySearchUpdatesTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(path), '--disable-sandbox', '--jobs', '4']).returncode)
