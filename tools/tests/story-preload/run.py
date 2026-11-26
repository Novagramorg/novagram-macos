import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryChatContent.swift')
parser.add_argument('--filter')
parser.add_argument('--skip')
args = parser.parse_args()
source = args.source.read_text()
def block(marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('public func ', 'func ')
markers = ['private func storyVideoPreloadRange(', 'private func storyMediaPreload(', 'public func preloadStoryMedia(', 'public func waitUntilStoryMediaPreloaded(']
production = '\n\n'.join(block(marker) for marker in markers if marker in source)
fixture = Path(__file__).with_name('StoryPreloadTests.swift').read_text().replace('__PRODUCTION__', production)
with tempfile.TemporaryDirectory(prefix='story-preload-') as directory:
    directory = Path(directory)
    ssk = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    ranges = json.dumps(str(root / 'submodules/telegram-ios/submodules/Utils/RangeSet'))
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "StoryPreload", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + ssk + '), .package(path: ' + ranges + ')], targets: [.testTarget(name: "StoryPreloadTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit"), .product(name: "RangeSet", package: "RangeSet")], path: "Tests")])\n')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryPreloadTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter: command += ['--filter', args.filter]
    if args.skip: command += ['--skip', args.skip]
    raise SystemExit(subprocess.run(command).returncode)
