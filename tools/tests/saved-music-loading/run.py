import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--core-source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Peers/SavedMusic.swift')
parser.add_argument('--ui-source', type=Path, default=root / 'packages/PeerMediaUI/Sources/PeerMediaUI/SendAudioModalController.swift')
args = parser.parse_args()
core = args.core_source.read_text()
start = core.index('public final class ProfileSavedMusicContext')
context = core[start:]
context = context.replace('public ', '')
start = core.index('private func updatedSavedMusicFiles(') if 'private func updatedSavedMusicFiles(' in core else core.index('func _internal_addSavedMusic(')
mutations = core[start:core.index('private final class CachedProfileSavedMusic', start)]
ui = args.ui_source.read_text()
start = ui.index('        updateState { current in', ui.index('let savedMusicContext =')) + len('        updateState { current in')
update = ui[start:ui.index('\n        }', start)]
start = ui.index('        let contentEmpty =')
empty = ui[start:ui.index('\n', start)]
start = ui.index('        if !state.savedMusicLoaded || !state.sharedAudioLoaded {')
loading = ui[start:ui.index('\n    } else {', start)]
start = ui.index('        if !state.sharedAudio.isEmpty {')
shared = ui[start:ui.index('            entries.append(.desc', start)] + '\n        }\n'
fixture = Path(__file__).with_name('SavedMusicTests.swift').read_text()
for key, value in [('__CONTEXT__', context), ('__MUTATIONS__', mutations), ('__UI_UPDATE__', update), ('__EMPTY__', empty), ('__LOADING__', shared + loading)]:
    fixture = fixture.replace(key, value)
with tempfile.TemporaryDirectory(prefix='saved-music-loading-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SavedMusicLoading", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "SavedMusicTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/SavedMusicTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
