import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--list-source', type=Path, default=root / 'packages/AudioPlayerUI/Sources/AudioPlayerUI/PlayerListController.swift')
parser.add_argument('--inline-source', type=Path, default=root / 'packages/AudioPlayerUI/Sources/AudioPlayerUI/InlineAudioPlayerView.swift')
args = parser.parse_args()
source = args.list_source.read_text()
start = source.index('        var played: Int?')
list_update = source[start:source.index('        needsLayout = true', start)]
source = args.inline_source.read_text()
start = source.index('        switch song.state {', source.index('    private func update(_ song:'))
inline_update = source[start:source.index('        switch controller.state.status', start)]
fixture = Path(__file__).with_name('ProgressTests.swift').read_text().replace('__LIST__', list_update).replace('__INLINE__', inline_update)
cases = ['normal', 'nan-progress', 'infinite-progress', 'progress-bounds', 'nan-current', 'invalid-duration', 'huge-time', 'negative-time', 'past-end', 'waiting', 'fetching', 'stopped']
with tempfile.TemporaryDirectory(prefix='audio-player-progress-') as directory:
    directory = Path(directory)
    (directory / 'main.swift').write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['swiftc', '-module-cache-path', str(Path(tempfile.gettempdir()) / 'audio-progress-module-cache'), str(directory / 'main.swift'), '-o', str(binary)], check=True)
    failed = 0
    for case in cases:
        result = subprocess.run([str(binary), case], capture_output=True, text=True)
        passed = result.returncode == 0
        failed += not passed
        print(f'{"PASS" if passed else "FAIL"} {case}')
        if not passed:
            print((result.stdout or result.stderr or f'Process exited {result.returncode}').splitlines()[0])
    print(f'{len(cases) - failed} passed; {failed} failed')
    raise SystemExit(bool(failed))
