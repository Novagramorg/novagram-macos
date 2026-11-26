import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/AudioPlayerCore/Sources/AudioPlayerCore/AudioPlayerController.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('private final class ControlCenter {')
control = source[start:source.index('public class APController :', start)].replace('private ', '')
control = control.replace('NSImage.init(contentsOfFile:', 'loadArtwork(contentsOfFile:').replace('NSImage(contentsOfFile:', 'loadArtwork(contentsOfFile:')
if 'func activate()' not in control:
    control += '\nextension ControlCenter { func activate() {} }\n'
start = source.index('        controlCenter.play =')
bindings = source[start:source.index('    @objc open func windowDidBecomeKey()', start)]
media = (root / 'packages/TelegramMedia/Sources/MediaPlayer.swift').read_text()
status = media[media.index('public enum MediaPlayerPlaybackStatus'):media.index('public final class MediaPlayer {')]
state = source[source.index('public enum APState'):source.index('public struct APResource')]
start = source.index('    public func setStatus(')
publish = source[start:source.index('    public func setProgress(', start)]
fixture = Path(__file__).with_name('ControlTests.swift').read_text().replace('__CONTROL__', control).replace('__BINDINGS__', bindings).replace('__STATUS__', status + state).replace('__PUBLISH__', publish)
cases = ['inactive-init', 'publish', 'old-clear', 'old-deinit', 'active-deinit', 'ownership-takeover', 'stale-publish', 'idempotent-setup', 'repeated-clear', 'reactivation', 'expired-command', 'late-command', 'released-player', 'availability', 'stale-availability', 'command-routing', 'seek-validation', 'background-command', 'background-deinit', 'background-deinit-takeover', 'paused-metadata', 'interpolated-metadata', 'inactive-metadata', 'invalid-metadata', 'bounded-metadata', 'publication-order', 'publication-reentry', 'buffering-publication']
cases += ['artwork-reuse', 'artwork-late', 'artwork-change', 'artwork-clear', 'artwork-takeover', 'artwork-deinit', 'artwork-queued', 'artwork-reactivate', 'artwork-corrupt', 'artwork-no-song-retention', 'artwork-background-release']
cases += ['artwork-background-delivery', 'artwork-same-resource-song']
with tempfile.TemporaryDirectory(prefix='audio-system-controls-') as directory:
    directory = Path(directory)
    path = directory / 'main.swift'
    path.write_text(fixture)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "AudioSystemControls", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + ')], targets: [.executableTarget(name: "Controls", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: ".", sources: ["main.swift"])])\n')
    subprocess.run(['swift', 'build', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4'], check=True)
    binary = directory / '.build/debug/Controls'
    failures = 0
    crashes = 0
    for case in cases:
        result = subprocess.run([str(binary), case], capture_output=True, text=True, timeout=20)
        failures += result.returncode != 0
        crashes += result.returncode < 0
        print(('PASS ' if result.returncode == 0 else 'FAIL ') + case)
        if result.returncode != 0:
            print((result.stdout or result.stderr or str(result.returncode)).splitlines()[0])
    print(f'{len(cases)-failures} passed; {failures} failed; {crashes} crashed')
    raise SystemExit(bool(failures))
