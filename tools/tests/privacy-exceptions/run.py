import argparse
import pathlib
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]


def read(name):
    path = f'packages/SettingsUI/Sources/SettingsUI/{name}.swift'
    if args.baseline:
        return subprocess.check_output(['git', '-C', str(root), 'show', f'HEAD:{path}'], text=True)
    return (root / path).read_text()


settings = read('SelectivePrivacySettingsController')
start = settings.index('                        var disableFor = current.disableFor', settings.index('updated: { updatedPeerIds in'))
end = settings.index('                    case .callP2P:', start)
apply_settings = 'private func applySettings(_ updatedPeerIds: [PeerId: SelectivePrivacyPeer], current: inout PrivacyState) {\n' + settings[start:end] + '}\n'
peers = read('SelectivePrivacySettingsPeersController')
start = peers.index('return context.account.postbox.transaction { transaction -> [SelectivePrivacyPeer] in')
start = peers.index('\n', start)
end = peers.index('                            return updatedPeers', start) + len('                            return updatedPeers')
apply_peers = 'private func applyPeers(_ peerIds: [PeerId], peers: [SelectivePrivacyPeer], transaction: Transaction) -> [SelectivePrivacyPeer] {\n' + peers[start:end] + '\n}\n'
categories = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift').read_text()
categories = categories[categories.index('public struct ChatListFilterPeerCategories:'):categories.index('private struct ChatListFilterPeerApiCategories:')]
extensions = (root / 'packages/TelegramUtils/Sources/TelegramUtils/PeerDisplay.swift').read_text()
extensions = extensions[extensions.index('extension ChatListFilterPeerCategories'):extensions.index('public final class TelegramStoryRepostPeerObject')]
package = pathlib.Path(tempfile.mkdtemp(prefix='telegram-privacy-exceptions-'))
tests = package / 'Tests'
tests.mkdir()
(package / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "PrivacyExceptionsRegression", targets: [.testTarget(name: "PrivacyExceptionsRegressionTests", path: "Tests")])
''')
fixture = pathlib.Path(__file__).with_name('PrivacyExceptionsRegressionTests.swift').read_text()
(tests / 'PrivacyExceptionsRegressionTests.swift').write_text('import Foundation\nimport XCTest\n\n' + categories + extensions + apply_settings + apply_peers + fixture)
print(f'Testing {"baseline" if args.baseline else "working tree"} privacy update closures in {package}', flush=True)
raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(package)]).returncode)
