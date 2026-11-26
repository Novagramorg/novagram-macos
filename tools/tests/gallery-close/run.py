import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/GalleryUI/Sources/GalleryUI/GalleryViewer.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('    public func close(_ animated:Bool')
close = source[start:source.index('    deinit {', start)]
start = source.index('    fileprivate func show(_ animated: Bool')
show = source[start:source.index('        NotificationCenter.default.removeObserver(self)', start)] + '    }'
property = '\n'.join(line for line in source.splitlines() if 'private var presentationGeneration' in line)
fixture = Path(__file__).with_name('GalleryCloseTests.swift').read_text()
for key, value in [('__CLOSE__', close), ('__SHOW__', show), ('__GENERATION__', property)]:
    fixture = fixture.replace(key, value)
with tempfile.TemporaryDirectory(prefix='gallery-close-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "GalleryClose", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "GalleryCloseTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/GalleryCloseTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
