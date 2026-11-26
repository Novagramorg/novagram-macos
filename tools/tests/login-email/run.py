import argparse
import pathlib
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
path = 'packages/PasskeysUI/Sources/PasskeysUI/SetupEmailController.swift'
source = subprocess.check_output(['git', '-C', str(root), 'show', f'HEAD:{path}'], text=True) if args.baseline else (root / path).read_text()
model = source[source.index('private final class Arguments'):source.index('private func entries(')]
controller = source[source.index('public func SetupEmailController('):].replace('public func SetupEmailController(', 'private func SetupEmailController(', 1)
package = pathlib.Path(tempfile.mkdtemp(prefix='telegram-login-email-'))
tests = package / 'Tests'
tests.mkdir()
dependency = root / 'submodules/telegram-ios/submodules/SSignalKit'
(package / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "LoginEmailRegression",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: "{dependency}")],
    targets: [.testTarget(name: "LoginEmailRegressionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
''')
fixture = pathlib.Path(__file__).with_name('LoginEmailRegressionTests.swift').read_text()
ui = (root / 'tools/tests/fixtures/SettingsWorkflowUI.swift').read_text()
(tests / 'LoginEmailRegressionTests.swift').write_text('import Foundation\nimport XCTest\nimport SwiftSignalKit\n\n' + model + controller + ui + fixture)
print(f'Testing {"baseline" if args.baseline else "working tree"} controller with simulated UI/backend and real SwiftSignalKit in {package}', flush=True)
raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(package)]).returncode)
