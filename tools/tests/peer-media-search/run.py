import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/PeerMediaUI/Sources/PeerMediaUI/PeerMediaPhotosController.swift')
parser.add_argument('--list-source', type=Path, default=root / 'packages/PeerMediaUI/Sources/PeerMediaUI/PeerMediaListController.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('        let history: Signal<')
history = source[start:source.index('        let historyView:', start)]
thread = '\n'.join(line for line in source.splitlines() if line.strip() == 'let threadId = self.threadInfo?.message.threadId')
fixture = Path(__file__).with_name('PeerMediaSearchTests.swift').read_text().replace('__HISTORY__', history).replace('__THREAD__', thread)
start = source.index('        genericView.setScrollHandler { [weak self] scroll in') + len('        genericView.setScrollHandler { [weak self] scroll in')
grid_scroll = source[start:source.index('            let view = historyView', start)]
fixture = fixture.replace('__GRID_SCROLL__', grid_scroll)
list_source = args.list_source.read_text()
start = list_source.index('                    let searchMessagesLocation:')
list_search = list_source[start:list_source.index('\n                }\n            }', start)]
start = list_source.index('        genericView.setScrollHandler { [weak self] scroll in')
list_scroll = list_source[start:list_source.index('\n        \n    }', start)]
list_fixture = Path(__file__).with_name('ListPaginationTests.swift').read_text().replace('__LIST_SEARCH__', list_search).replace('__LIST_SCROLL__', list_scroll)
pagination = (root / 'packages/PeerMediaUI/Sources/PeerMediaUI/PeerMediaSearchPagination.swift').read_text().replace('import Postbox\n', '').replace('import TelegramCore\n', '')
with tempfile.TemporaryDirectory(prefix='peer-media-search-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PeerMediaSearch", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "PeerMediaSearchTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PeerMediaSearchTests.swift').write_text(fixture)
    (directory / 'Tests/PeerMediaSearchPagination.swift').write_text(pagination)
    (directory / 'Tests/PaginationTests.swift').write_text(Path(__file__).with_name('PaginationTests.swift').read_text())
    (directory / 'Tests/ListPaginationTests.swift').write_text(list_fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
