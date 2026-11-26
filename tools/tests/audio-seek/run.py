import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/AudioPlayerCore/Sources/AudioPlayerCore/AudioPlayerController.swift')
args = parser.parse_args()
source = args.source.read_text()
media = (root / 'packages/TelegramMedia/Sources/MediaPlayer.swift').read_text()

def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]

fixture = Path(__file__).with_name('SeekTests.swift').read_text()
for key, value in [
    ('__STATUS__', section(media, 'public enum MediaPlayerPlaybackStatus', 'public final class MediaPlayer {')),
    ('__STATE__', section(source, 'public enum APState', 'public struct APResource')),
    ('__PROGRESS__', section(source, '    public func setProgress(', '    private var _state:')),
    ('__SEEK__', section(source, '    @discardableResult public func set(trackProgress:', '    public func cleanup()')),
]:
    fixture = fixture.replace(key, value)
cases = ['quarter', 'start', 'bounds', 'invalid-position', 'invalid-duration', 'unavailable', 'fraction', 'fraction-bounds', 'invalid-fraction', 'item-validation', 'playing', 'buffering']
with tempfile.TemporaryDirectory(prefix='audio-seek-') as directory:
    directory = Path(directory)
    (directory / 'main.swift').write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['swiftc', '-module-cache-path', str(Path(tempfile.gettempdir()) / 'audio-seek-module-cache'), str(directory / 'main.swift'), '-o', str(binary)], check=True)
    failed = 0
    for case in cases:
        result = subprocess.run([str(binary), case], capture_output=True, text=True)
        passed = result.returncode == 0
        failed += not passed
        print(f'{"PASS" if passed else "FAIL"} {case}')
        if not passed:
            print(result.stdout)
    print(f'{len(cases) - failed} passed; {failed} failed')
    raise SystemExit(bool(failed))
