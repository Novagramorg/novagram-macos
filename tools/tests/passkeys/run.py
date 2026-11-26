import argparse
import pathlib
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
submodule = root / 'submodules/telegram-ios'
source_path = 'submodules/TelegramCore/Sources/Account/Account.swift'
if args.baseline:
    source = subprocess.check_output(['git', '-C', str(submodule), 'show', f'HEAD:{source_path}'], text=True)
else:
    source = (submodule / source_path).read_text()
implementation = source[source.index('func _internal_deletePasskey('):source.index('func _internal_requestPasskeyLoginData(')]
package = pathlib.Path(tempfile.mkdtemp(prefix='telegram-passkeys-'))
tests = package / 'Tests'
tests.mkdir()
dependency = submodule / 'submodules/SSignalKit'
(package / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "PasskeysRegression",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: "{dependency}")],
    targets: [.testTarget(name: "PasskeysRegressionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
''')
fixture = pathlib.Path(__file__).with_name('PasskeysRegressionTests.swift').read_text()
(tests / 'PasskeysRegressionTests.swift').write_text('import Foundation\nimport XCTest\nimport SwiftSignalKit\n\n' + implementation + fixture)
print(f'Testing {"baseline" if args.baseline else "working tree"} implementation in {package}', flush=True)
raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(package)]).returncode)
