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
def block(text, marker):
    start = text.index(marker); end = text.index('{', start) + 1; depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}'); end += 1
    return text[start:end].replace('public ', '')
fixture = Path(__file__).with_name('StoryPeerPollTests.swift').read_text()
fixture = fixture.replace('__POLL__', block(source, 'public func _internal_pollPeerStories('))
stories = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift').read_text()
fixture = fixture.replace('__ORDERING__', '\n'.join(block(stories, marker) for marker in ['final class PeerStoryPollContext {', 'final class PeerStoryPollLease {', 'func _internal_invalidatePeerStoryPoll(', 'func _internal_invalidateStoryResolution(', 'private final class StoryResolutionContextRegistry {']))
fixture = fixture.replace('__EXISTING__', block(stories, 'func _internal_existingStoryItem('))
with tempfile.TemporaryDirectory(prefix='story-peer-poll-') as directory:
    path = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (path / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "StoryPeerPoll", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + ')], targets: [.testTarget(name: "StoryPeerPollTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (path / 'Tests').mkdir()
    (path / 'Tests/StoryPeerPollTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(path), '--disable-sandbox', '--jobs', '4']).returncode)
