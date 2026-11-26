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
a = viewer.index('        }, togglePinned: { [weak self] story in'); b = viewer.index('        }, hashtag:', a)
view_action = viewer[a:b].replace('        }, togglePinned: { [weak self] story in','        self.toggleProfile = { [weak self] story in',1) + '\n        }\n'
helper = ''
if '        let setProfileStories:' in grid:
    a = grid.index('        let setProfileStories:'); helper = grid[a:grid.index('        let pinStories:',a)]
a = grid.index('        }, archiveSelected: { [weak self] in'); b = grid.index('        }, deleteStory:',a)
actions = grid[a:b].replace('        }, archiveSelected: { [weak self] in','        self.archiveSelected = { [weak self] in',1).replace('        }, toggleStory: { story in','        }\n        self.toggleStory = { story in',1) + '\n        }\n'
viewer_disposal = '\n'.join(line for line in viewer[viewer.rindex('    deinit {'):].splitlines() if line.strip() in ['deleteStoryDisposable.dispose()', 'profileStoryDisposable.dispose()'])
fixture = Path(__file__).with_name('StoryProfileUITests.swift').read_text()
for key, value in [('__VIEW_ACTION__',view_action),('__HELPER__',helper),('__ACTIONS__',actions),('__VIEW_DISAPPEAR__',method(viewer,'    public override func viewWillDisappear')),('__VIEW_APPEAR__',method(viewer,'    public override func viewWillAppear')),('__VIEW_DISPOSAL__',viewer_disposal),('__GRID_DISAPPEAR__',method(grid,'    public override func viewWillDisappear')),('__GRID_APPEAR__',method(grid,'    public override func viewWillAppear')),('__GRID_DEINIT__',method(grid,'    deinit {'))]:
    fixture = fixture.replace(key, value)
with tempfile.TemporaryDirectory(prefix='story-profile-ui-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryProfileUI", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "StoryProfileUITests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryProfileUITests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
