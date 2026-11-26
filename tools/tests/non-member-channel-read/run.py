import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
path = 'packages/ChatUI/Sources/ChatUI/ChatController.swift'
source = subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:' + path], text=True) if args.baseline else (root / path).read_text()
start = source.index('        let previousMaxIncomingMessageIdByNamespace =')
end = source.index('        self.readHistoryDisposable.set(readHistory.start())', start)
end += len('        self.readHistoryDisposable.set(readHistory.start())')
implementation = source[start:end]
helper = ''
if 'private func chatHistoryKeepsReadState(' in source:
    start = source.index('private func chatHistoryKeepsReadState(')
    end = source.index('\nprivate var nextClientId', start)
    helper = source[start:end]
package = Path(tempfile.mkdtemp(prefix='telegram-nonmember-read-'))
tests = package / 'Tests'
tests.mkdir()
dependency = root / 'submodules/telegram-ios/submodules/SSignalKit'
(package / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "NonMemberReadRegression", platforms: [.macOS(.v10_13)], dependencies: [.package(name: "SSignalKit", path: "{dependency}")], targets: [.testTarget(name: "NonMemberReadRegressionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
fixture = Path(__file__).with_name('ReadHistoryTests.swift').read_text()
(tests / 'ReadHistoryTests.swift').write_text(fixture.replace('__HELPER__', helper).replace('__IMPLEMENTATION__', implementation))
environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(package / 'cache'), SWIFTPM_MODULECACHE_OVERRIDE=str(package / 'cache'))
print('Testing extracted ' + ('HEAD' if args.baseline else 'working-tree') + ' read pipeline in ' + str(package), flush=True)
raise SystemExit(subprocess.run(['swift', 'test', '--disable-sandbox', '--jobs', '4', '--package-path', str(package)], env=environment).returncode)
