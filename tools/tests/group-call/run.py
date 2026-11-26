import argparse
import os
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
path = 'packages/TelegramCallsCore/Sources/TelegramCallsCore/PresentationGroupCall.swift'
source = subprocess.check_output(['git', '-C', str(root), 'show', f'HEAD:{path}'], text=True) if args.baseline else (root / path).read_text()
source = source[source.index('public final class PresentationGroupCallImpl:'):]


def method(signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('public ', '').replace('private ', '')


signatures = [
    'public func setIsMuted(action:',
    'public func requestScreencast(deviceId: OngoingCallVideoCapturer',
    'public func disableScreencast()',
    'public func requestVideo(deviceId: OngoingCallVideoCapturer',
    'public func disableVideo()',
    'public func setSuspendVideoChannelRequests(',
    'public func setRequestedVideoList(',
    'private func markAsCanBeRemoved()',
]
methods = '\n\n'.join(method(signature) for signature in signatures)
if 'private func applyParticipantMuteState(' in source:
    methods += '\n' + method('private func applyParticipantMuteState(')
else:
    methods += '\nfunc applyParticipantMuteState(_ muteState: GroupCallParticipantsContext.Participant.MuteState?) {}'
start = source.index('                if !self.didApplyInitialOutput {') if 'if !self.didApplyInitialOutput' in source else source.index('                if !self.initialOutput.isMuted {')
end = source.index('                let myPeer =', start)
methods += '\nfunc establishParticipantsContext() {\nlet participantsContext = self.participantsContext!\n' + source[start:end] + '\n}'
package = pathlib.Path(tempfile.mkdtemp(prefix='telegram-group-call-regression-'))
tests = package / 'Tests'
tests.mkdir()
dependency = root / 'submodules/telegram-ios/submodules/SSignalKit'
(package / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "GroupCallRegression",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: "{dependency}")],
    targets: [.testTarget(name: "GroupCallRegressionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
''')
fixture = pathlib.Path(__file__).with_name('GroupCallRegressionTests.swift').read_text()
(tests / 'GroupCallRegressionTests.swift').write_text(fixture.replace('METHODS_FROM_SOURCE', methods))
print(f'Testing {"baseline" if args.baseline else "working tree"} methods with simulated media/backend and real SwiftSignalKit in {package}', flush=True)
env = dict(os.environ, CLANG_MODULE_CACHE_PATH='/tmp/telegram-group-call-module-cache')
raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(package), '--disable-sandbox', '--cache-path', '/tmp/telegram-group-call-spm-cache'], env=env).returncode)
