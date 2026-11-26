import argparse
import re
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/PeerMediaUI/Sources/PeerMediaUI/SendAudioModalController.swift')
parser.add_argument('--row-source', type=Path, default=root / 'packages/PeerMediaUI/Sources/PeerMediaUI/PeerMediaMusicRowContent.swift')
args = parser.parse_args()
source = args.source.read_text()
row = args.row_source.read_text()

def section(start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

saved = section('            let messageId = MessageId', '            return Message(')
bot_start = source.index('                            if let file = internalReference.file {')
bot_start = source.index('\n', bot_start) + 1
bot = source[bot_start:source.index('                                messages.append(Message(', bot_start)]
if 'let messageId =' not in bot:
    bot += '\nlet messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: Int32(stableId))\n'
ids = section('private func _id_saved', 'private func audioViewType')
merge = section('                    var allMessages = shared', '                    current.searchResults = allMessages')
mapping = section('private final class SendAudioMessageIds', 'private final class SendAudioArguments') if 'private final class SendAudioMessageIds' in source else 'private final class SendAudioMessageIds {}'
playing = re.search(r'if let controller = controller, (.+) \{', source).group(1)
wrapper = re.search(r'let wrapper = APSingleWrapper\(.*id: (.*)\)', source).group(1)
row_playing = re.search(r'let isCurrentSong = (.+)', row)
row_playing = row_playing.group(1) if row_playing else re.search(r'if (song.entry.isEqual\(to: item.message.id\)) \{', row).group(1)
menu = re.search(r'public override func menuItems\(.*?\n\s*if (.+) \{', row).group(1)
fixture = Path(__file__).with_name('IdentityTests.swift').read_text()
for key, value in [('__SAVED__', saved), ('__BOT__', bot), ('__IDS__', ids), ('__MERGE__', merge), ('__MAPPING__', mapping), ('__PLAYING__', playing), ('__WRAPPER__', wrapper), ('__ROW_PLAYING__', row_playing), ('__MENU__', menu)]:
    fixture = fixture.replace(key, value)
with tempfile.TemporaryDirectory(prefix='send-audio-identity-') as directory:
    directory = Path(directory)
    (directory / 'main.swift').write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['swiftc', '-module-cache-path', str(Path(tempfile.gettempdir()) / 'send-audio-identity-module-cache'), str(directory / 'main.swift'), '-o', str(binary)], check=True)
    failed = 0
    cases = ['saved-collision', 'bot-collision', 'negative-ids', 'cross-source', 'stable', 'media-namespace', 'concurrent-mapping', 'row-namespace', 'row-peer', 'bot-duplicates', 'shared-order', 'playback-collision', 'playback-same-resource', 'wrapper-identity', 'modal-playing-row', 'chat-playing-row', 'modal-menu', 'chat-menu']
    for case in cases:
        result = subprocess.run([str(binary), case], capture_output=True, text=True)
        passed = result.returncode == 0
        failed += not passed
        print(f'{"PASS" if passed else "FAIL"} {case}')
        if not passed:
            print(result.stdout)
    print(f'{len(cases) - failed} passed; {failed} failed')
    raise SystemExit(bool(failed))
