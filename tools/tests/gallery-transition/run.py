from pathlib import Path
import argparse
import os
import resource
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/GalleryUI/Sources/GalleryUI/GalleryViewer.swift')
args = parser.parse_args()
source = args.source.read_text()

def section(start, end):
    offset = source.index(start) + len(start)
    return source[offset:source.index(end, offset)]

fixture = Path(__file__).with_name('GalleryTransitionTests.swift').read_text()
fixture = fixture.replace('__OPEN__', section('strongSelf.pager.animateIn(from: { [weak strongSelf] stableId -> NSView? in', '}, completion:'))
fixture = fixture.replace('__CLOSE__', section('self.pager.animateOut(to: { [weak self] stableId in', '}, completion:'))
cases = ['valid', 'removed-last', 'empty', 'negative', 'missing-view', 'missing-owner', 'direct', 'ignored', 'changed']
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
with tempfile.TemporaryDirectory(prefix='gallery-transition-') as directory:
    directory = Path(directory)
    swift = directory / 'main.swift'
    swift.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['swiftc', '-module-cache-path', str(Path(tempfile.gettempdir()) / 'gallery-transition-module-cache'), str(swift), '-o', str(binary)], check=True)
    failed = 0
    for direction in ['open', 'close']:
        for case in cases:
            result = subprocess.run([str(binary), direction, case], capture_output=True, text=True,
                                    env={**os.environ, 'SWIFT_BACKTRACE': 'enable=no'})
            passed = result.returncode == 0
            failed += not passed
            print(f'{"PASS" if passed else "FAIL"} {direction}/{case}' + (f' (exit {result.returncode})' if not passed else ''))
            if not passed and result.returncode > 0:
                print(result.stdout + result.stderr)
    print(f'{len(cases) * 2 - failed} passed; {failed} failed')
    raise SystemExit(bool(failed))
