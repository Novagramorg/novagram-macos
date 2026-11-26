import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/SettingsUI/Sources/SettingsUI/EditAccountInfoController.swift')
args = parser.parse_args()
s = args.source.read_text()
def block(source, marker):
    a = source.index(marker); b = source.index('{', a) + 1; depth = 1
    while depth:
        depth += (source[b] == '{') - (source[b] == '}'); b += 1
    return source[a:b]
fixture = Path(__file__).with_name('ProfilePhotoTests.swift').read_text()
fixture = fixture.replace('__PHOTO__', block(s, '    let updatePhoto:'))
fixture = fixture.replace('__VIDEO__', block(s, '    let updateVideo:'))
fixture = fixture.replace('__CANCEL__', block(s, '    let cancel ='))
fixture = fixture.replace('__REMOVAL__', block(s, 'afterDisappear:').split('afterDisappear: ', 1)[1])
fixture = fixture.replace('__DEINIT__', block(s, '    controller.onDeinit =').split(' = ', 1)[1])
helper = root / 'packages/SettingsUI/Sources/SettingsUI/EditAccountPhotoAction.swift'
fixture = fixture.replace('__HELPER__', '\n'.join(line for line in helper.read_text().splitlines() if not line.startswith('import ')) if helper.exists() else 'final class EditAccountPhotoAction: Disposable {func dispose() {}}')
with tempfile.TemporaryDirectory(prefix='profile-photo-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ProfilePhoto", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit')) + ''')], targets: [.testTarget(name: "ProfilePhotoTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ProfilePhotoTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
