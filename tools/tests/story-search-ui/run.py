import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--screen', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryFoundListController.swift')
parser.add_argument('--grid', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryMonthRowItem.swift')
parser.add_argument('--filter')
parser.add_argument('--skip')
parser.add_argument('--empty-row', type=Path, default=root / 'packages/GeneralRows/Sources/GeneralRows/SearchEmptyRowItem.swift')
args = parser.parse_args()
screen = args.screen.read_text()
grid = args.grid.read_text()
empty_row = args.empty_row.read_text()
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('public override', 'override').replace('public ', '')
action = block(empty_row, '            if let action = item.buttonAction')
if '            } else if let action = self.action {' in empty_row:
    action += ' else ' + block(empty_row, 'if let action = self.action {')
fixture = Path(__file__).with_name('StorySearchUITests.swift').read_text()
a = screen.index('private let _id_map_map')
b = screen.index('private extension SearchStoryListContext.Source', a)
for key, value in [
    ('__ARGUMENTS__', block(screen, 'private final class Arguments')),
    ('__STATE__', block(screen, 'private struct State')),
    ('__ENTRIES__', screen[a:b]),
    ('__SOURCE__', block(screen, 'private extension SearchStoryListContext.Source')),
    ('__CONTROLLER__', block(screen, 'public func StoryFoundListController')),
    ('__MAP_SET__', block(screen, '    public override func set(item:')),
    ('__EMPTY_ACTION__', action),
    ('__GRID_SIZE__', block(grid, '    public override func makeSize('))
]:
    fixture = fixture.replace(key, value)
if 'loadMore: @escaping' not in screen:
    fixture = fixture.replace('}, loadMore: { self.loads += 1 })', '})')
with tempfile.TemporaryDirectory(prefix='story-search-ui-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StorySearchUI", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StorySearchUITests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StorySearchUITests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter:
        command += ['--filter', args.filter]
    if args.skip:
        command += ['--skip', args.skip]
    raise SystemExit(subprocess.run(command).returncode)
