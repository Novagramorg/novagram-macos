import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path)
parser.add_argument('--legacy', action='store_true')
args = parser.parse_args()
source = root / 'submodules/telegram-ios/submodules/SSignalKit' / ('SwiftSignalKit' if args.legacy else 'SwiftSignalKit2') / 'Source'
with tempfile.TemporaryDirectory(prefix='signal-queue-ownership-') as directory:
    directory=Path(directory)
    shutil.copytree(source,directory/'Sources')
    if args.source: shutil.copyfile(args.source,directory/'Sources/Signal_Meta.swift')
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SignalQueueOwnership", platforms: [.macOS(.v10_13)], targets: [.target(name: "SwiftSignalKit", path: "Sources"), .testTarget(name: "SignalQueueTests", dependencies: ["SwiftSignalKit"], path: "Tests")])
''')
    (directory/'Tests').mkdir();shutil.copyfile(Path(__file__).with_name('SignalQueueTests.swift'),directory/'Tests/SignalQueueTests.swift')
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
