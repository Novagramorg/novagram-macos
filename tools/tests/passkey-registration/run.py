import argparse
import pathlib
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
path = 'packages/PasskeysUI/Sources/PasskeysUI/PasskeysController.swift'
source = subprocess.check_output(['git', '-C', str(root), 'show', f'HEAD:{path}'], text=True) if args.baseline else (root / path).read_text()
encoding = source[source.index('private let encodeBase64URL:'):source.index('private final class EmptyRowItem')]
model_start = source.index('private enum PasskeyCreationError:') if 'private enum PasskeyCreationError:' in source else source.index('private final class Arguments {')
model = source[model_start:source.index('private let _id_empty')]
controller = source[source.index('@available(macOS 12.0, *)\nprivate class Delegate'):].replace('public func PasskeysController(', 'private func PasskeysController(', 1)
package = pathlib.Path(tempfile.mkdtemp(prefix='telegram-passkey-registration-'))
tests = package / 'Tests'
tests.mkdir()
dependency = root / 'submodules/telegram-ios/submodules/SSignalKit'
(package / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "PasskeyRegistrationRegression",
    platforms: [.macOS(.v12)],
    dependencies: [.package(name: "SSignalKit", path: "{dependency}")],
    targets: [.testTarget(name: "PasskeyRegistrationRegressionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
''')
fixture = pathlib.Path(__file__).with_name('PasskeyRegistrationRegressionTests.swift').read_text()
ui = (root / 'tools/tests/fixtures/SettingsWorkflowUI.swift').read_text()
(tests / 'PasskeyRegistrationRegressionTests.swift').write_text('import Foundation\nimport XCTest\nimport SwiftSignalKit\n\n' + encoding + model + controller + ui + fixture)
print(f'Testing {"baseline" if args.baseline else "working tree"} controller/delegate with simulated UI/backend and real SwiftSignalKit in {package}', flush=True)
raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(package)]).returncode)
