from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatDateMessageCount.swift').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('import '))
fixture = Path(__file__).with_name('DateCountTests.swift').read_text().replace('__PRODUCTION__', source)
with tempfile.TemporaryDirectory(prefix='chat-date-count-') as directory:
    path = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (path / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatDateCount", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatDateCountTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (path / 'Tests').mkdir()
    (path / 'Tests/DateCountTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(path), '--disable-sandbox', '--jobs', '4']).returncode)
