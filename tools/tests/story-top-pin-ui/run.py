import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryMediaController.swift')
args = parser.parse_args()
source = args.source.read_text()
def method(marker):
    start = source.index(marker); brace = source.index('{', start); depth = 1; end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public override', 'override')
helper = ''
if '        let pinStories:' in source:
    start = source.index('        let pinStories:')
    helper = source[start:source.index('        let deleteStories:', start)]
start = source.index('        }, togglePinned: { [weak self] story in')
end = source.index('        }, collection:', start)
actions = source[start:end].replace('        }, togglePinned: { [weak self] story in', '        self.togglePinned = { [weak self] story in', 1).replace('        }, togglePinSelected: { [weak self] in','        }\n        self.togglePinSelected = { [weak self] in',1) + '\n        }\n'
fixture = Path(__file__).with_name('StoryTopPinUITests.swift').read_text()
for key, value in [('__HELPER__', helper), ('__ACTIONS__', actions), ('__DISAPPEAR__',method('    public override func viewWillDisappear')),('__APPEAR__',method('    public override func viewWillAppear')),('__DEINIT__',method('    deinit {')), ('__STATE__', method('    var state:PeerStoryListContext.State?').replace('PeerStoryListContext.State', 'ListState')), ('__MAIN_STATE__', method('    var mainState: PeerStoryListContext.State?').replace('PeerStoryListContext.State', 'ListState'))]:
    fixture = fixture.replace(key, value)
with tempfile.TemporaryDirectory(prefix='story-top-pin-ui-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryTopPinUI", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StoryTopPinUITests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryTopPinUITests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
