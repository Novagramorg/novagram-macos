import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('private func apiInputPrivacyRules(')
conversion = source[start:source.index('public struct StoryUploadInfo', start)].replace('private func', 'func')
start = source.index('                var parsedPrivacy: Stories.Item.Privacy?')
parsing = source[start:source.index('                let isPinned =', start)]
parsing = 'func parsePrivacy(_ privacy: [Api.PrivacyRule]?, transaction: Transaction) -> Stories.Item.Privacy? {\n' + parsing + '\nreturn parsedPrivacy\n}'
utils = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/ApiUtils/ApiUtils.swift').read_text()
start = utils.index('func apiInputUser(_ peer: Peer)')
input_user = utils[start:utils.index('func apiInputUser(_ peer: Peer,', start)]
fixture = Path(__file__).with_name('StoryPrivacyRulesTests.swift').read_text().replace('__SOURCE__', '\n'.join([conversion, parsing, input_user]))
with tempfile.TemporaryDirectory(prefix='story-privacy-rules-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryPrivacyRules", targets: [.testTarget(name: "StoryPrivacyRulesTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryPrivacyRulesTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
