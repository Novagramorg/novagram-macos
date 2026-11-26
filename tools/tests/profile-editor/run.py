import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/SettingsUI/Sources/SettingsUI/EditAccountInfoController.swift')
parser.add_argument('--filter')
args = parser.parse_args()
s = args.source.read_text()
def block(source, marker):
    a = source.index(marker)
    b = source.index('{', a) + 1
    depth = 1
    while depth:
        depth += (source[b] == '{') - (source[b] == '}')
        b += 1
    return source[a:b]
state = block(s, 'public struct EditInfoState')
state = state.replace(block(state, '    public init(_ peerView:'), '')
helper = (root / 'packages/SettingsUI/Sources/SettingsUI/EditAccountProfileSaveAction.swift').read_text()
helper = '\n'.join(line for line in helper.splitlines() if not line.startswith('import '))
fixture = Path(__file__).with_name('ProfileEditorTests.swift').read_text()
fixture = fixture.replace('__HELPER__', helper).replace('__STATE__', state.replace('public ', ''))
fixture = fixture.replace('__VALUES__', block(s, 'private func valuesRequiringUpdate').replace('private func', 'func'))
fixture = fixture.replace('__VALIDATE__', block(s, 'validateData:').split('validateData: ', 1)[1])
fixture = fixture.replace('__UPDATE__', block(s, 'updateDatas:').split('updateDatas: ', 1)[1])
fixture = fixture.replace('__HOOKS__', '\n'.join(block(s, '    controller.' + name + ' =') for name in ['willDisappear', 'willAppear', 'onDeinit'] if '    controller.' + name + ' =' in s))
with tempfile.TemporaryDirectory(prefix='profile-editor-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ProfileEditor", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ProfileEditorTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ProfileEditorTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter:
        command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
