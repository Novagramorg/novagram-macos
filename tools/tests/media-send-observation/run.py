from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift').read_text()
start = source.index('    public static func enqueue(media:Media,')
fixture = Path(__file__).with_name('MediaSendTests.swift').read_text()
fixture = fixture.replace('__MEDIA_SEND__', source[start:source.rindex('}')].replace('public static func', 'static func'))
with tempfile.TemporaryDirectory(prefix='media-send-observation-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MediaSendObservation", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "MediaSendObservationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/MediaSendTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
