import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--viewer', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryModalController.swift')
parser.add_argument('--grid', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryMediaController.swift')
args = parser.parse_args()
viewer = args.viewer.read_text(); grid = args.grid.read_text()
def method(source, marker):
    start = source.index(marker); brace = source.index('{', start); depth = 1; end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public override', 'override')
start = viewer.index('        let deleteStory:(StoryContentItem)->Void =')
view_delete = viewer[start:viewer.index('        self.chatInteraction.add(observer: self)', start)]
helper = ''
if '        let deleteStories: ([Int32],' in grid:
    start = grid.index('        let deleteStories: ([Int32],')
    helper = grid[start:grid.index('        let arguments = Arguments(', start)]
start = grid.index('        }, deleteStory: { story in')
end = grid.index('        }, togglePinned:', start)
actions = grid[start:end].replace('        }, deleteStory: { story in', '        self.deleteSingle = { story in', 1).replace('        }, deleteSelected: { [weak self] in','        }\n        self.deleteSelected = { [weak self] in',1) + '\n        }\n'
fixture = Path(__file__).with_name('StoryDeleteUITests.swift').read_text()
for key,value in [('__VIEW_DELETE__',view_delete),('__VIEW_DISAPPEAR__',method(viewer,'    public override func viewWillDisappear')),('__GRID_HELPER__',helper),('__GRID_ACTIONS__',actions),('__GRID_DISAPPEAR__',method(grid,'    public override func viewWillDisappear')),('__GRID_APPEAR__',method(grid,'    public override func viewWillAppear'))]: fixture=fixture.replace(key,value)
with tempfile.TemporaryDirectory(prefix='story-delete-ui-') as directory:
    directory=Path(directory)
    dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryDeleteUI", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "StoryDeleteUITests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryDeleteUITests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
