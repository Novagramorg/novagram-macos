import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--baseline-crashes', action='store_true')
args = parser.parse_args()
args.baseline = args.baseline or args.baseline_crashes

def source(name):
    path = Path('/tmp') / (name + '-before-recording-trim.swift') if args.baseline else root / 'packages/ChatUI/Sources/ChatUI' / (name + '.swift')
    return path.read_text()

def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

scrubber = source('RecordingTrimScrubberView')
markers = ['private struct DragState', 'private func performSeek', 'private func beginDrag', 'private func endDrag', 'private func moveDrag', 'private func trackWidth', 'private var minimumTrimDuration', 'private func clamp01', 'private func snap', 'private func handleOriginX', 'private func value(forX', 'private func updateDurationText', 'public func update(duration:', 'public func updateLayout', 'public override func viewDidMoveToWindow', 'public func setVideo']
methods = '\n'.join(block(scrubber, marker).replace('private ', '').replace('public ', '') for marker in markers)
input_source = source('ChatInputRecordingView')
input_methods = '\n'.join(block(input_source, marker).replace('private ', '') for marker in ['private func applyPreview', 'private func updateTrim'])
fixture = Path(__file__).with_name('RecordingTrimTests.swift').read_text()
fixture = fixture.replace('__METHODS__', methods).replace('__INPUT__', input_methods)
fixture = fixture.replace('__METRICS__', block(scrubber, 'private enum Metrics').replace('private ', ''))
fixture = fixture.replace('__WAVEFORM__', block(scrubber, 'private final class TrimWaveformLayer').replace('private ', '').replace('public ', ''))
fixture = fixture.replace('__STATE__', (root / 'packages/ChatUI/Sources/ChatUI/RecordingTrimState.swift').read_text())
with tempfile.TemporaryDirectory(prefix='recording-trim-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RecordingTrim", targets: [.testTarget(name: "TrimTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/RecordingTrimTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    environment = dict(os.environ, TRIM_BASELINE='1' if args.baseline else '0', TRIM_UNSAFE='1' if args.baseline_crashes else '0')
    if args.baseline_crashes:
        subprocess.run(command + ['--filter', '^NoMatchingTests$'], env=environment, check=True)
        for name in ['TrimTests/testInvalidDurationIsEmpty', 'TrimTests/testOversizedDurationLabelDoesNotTrap', 'PreviewTests/testShorterPreviewOutsideOldRangeResetsSelection', 'PreviewTests/testVideoPreviewUsesSameRangeValidation', 'WaveformTests/testInfiniteWaveformDoesNotTrap']:
            result = subprocess.run(command + ['--skip-build', '--filter', name], env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            crashed = result.returncode != 0 and 'unexpected signal code' in result.stdout and name.split('/')[1] + "]' started." in result.stdout
            print(name + ': ' + ('confirmed original crash' if crashed else 'unexpected result'), flush=True)
            if not crashed:
                print(result.stdout)
                raise SystemExit(1)
    else:
        raise SystemExit(subprocess.run(command, env=environment).returncode)
