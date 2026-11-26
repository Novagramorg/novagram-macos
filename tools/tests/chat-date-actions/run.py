from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source_directory = root / 'packages/ChatUI/Sources/ChatUI'
for name in ('chatDateLoadMessages', 'chatDateMessageCount'):
    declarations = sum(path.read_text().count('func ' + name + '(') for path in source_directory.glob('*.swift'))
    assert declarations == 1, f'{name}: expected one declaration, found {declarations}'
source = '\n'.join((source_directory / name).read_text() for name in ('ChatDateMessageCount.swift', 'ChatDateHeaderActions.swift'))
source = '\n'.join(line for line in source.splitlines() if not line.startswith('import '))
fixture = Path(__file__).with_name('DateActionsTests.swift').read_text().replace('__PRODUCTION__', source)
with tempfile.TemporaryDirectory(prefix='chat-date-actions-') as directory:
    path = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (path / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatDateActions", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatDateActionsTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (path / 'Tests').mkdir()
    (path / 'Tests/DateActionsTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(path), '--disable-sandbox', '--jobs', '4']).returncode)
