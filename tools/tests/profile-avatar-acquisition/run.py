import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root/'packages/SettingsUI/Sources/SettingsUI/EditAccountInfoController.swift')
args = parser.parse_args()
s = args.source.read_text()
def block(marker):
    a = s.index(marker)
    a = s.index('{', a)
    b = a + 1
    depth = 1
    while depth:
        depth += (s[b] == '{') - (s[b] == '}')
        b += 1
    return s[a:b]
fixture = Path(__file__).with_name('AvatarAcquisitionTests.swift').read_text()
fixture = fixture.replace('__PICKER__', block('    let arguments = EditInfoControllerArguments(context: context, uploadNewPhoto: { control in'))
fixture = fixture.replace('__REMOVAL__', block('afterDisappear:'))
fixture = fixture.replace('__HOOKS__', '\n'.join('controller.' + name + ' = ' + block('    controller.' + name + ' =') for name in ['willAppear', 'willDisappear', 'onDeinit']))
helper = (root/'packages/SettingsUI/Sources/SettingsUI/EditAccountAvatarAcquisition.swift').read_text()
fixture = fixture.replace('__HELPER__', '\n'.join(x for x in helper.splitlines() if not x.startswith('import ')))
with tempfile.TemporaryDirectory(prefix='profile-avatar-acquisition-') as directory:
    directory = Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package=Package(name:"AvatarAcquisition",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')],targets:[.testTarget(name:"AvatarAcquisitionTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Tests")])
''')
    (directory/'Tests').mkdir()
    (directory/'Tests/AvatarAcquisitionTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
