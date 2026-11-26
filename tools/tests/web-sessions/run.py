import argparse
import pathlib
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
submodule = root / 'submodules/telegram-ios'


def read_source(name):
    path = f'submodules/TelegramCore/Sources/TelegramEngine/Privacy/{name}.swift'
    if args.baseline:
        return subprocess.check_output(['git', '-C', str(submodule), 'show', f'HEAD:{path}'], text=True)
    return (submodule / path).read_text()


context = read_source('ActiveSessionsContext')
context = context[context.index('public struct WebSessionsContextState:'):]
sessions = read_source('RecentWebSessions')
authorization = sessions[sessions.index('public struct WebAuthorization'):sessions.index('func webSessions(')]
requests = sessions[sessions.index('func terminateWebSession('):]
package = pathlib.Path(tempfile.mkdtemp(prefix='telegram-web-sessions-'))
tests = package / 'Tests'
tests.mkdir()
dependency = submodule / 'submodules/SSignalKit'
(package / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "WebSessionsRegression",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: "{dependency}")],
    targets: [.testTarget(name: "WebSessionsRegressionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
''')
fixture = pathlib.Path(__file__).with_name('WebSessionsRegressionTests.swift').read_text()
(tests / 'WebSessionsRegressionTests.swift').write_text('import Foundation\nimport XCTest\nimport SwiftSignalKit\n\n' + authorization + requests + context + fixture)
print(f'Testing {"baseline" if args.baseline else "working tree"} implementation in {package}', flush=True)
raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(package)]).returncode)
