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
media = (root / 'packages/TelegramMedia/Sources/MediaPlayer.swift').read_text()

def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]

fixture = Path(__file__).with_name('PlaybackTests.swift').read_text()
for key, value in [
    ('__STATUS__', section(media, 'public enum MediaPlayerPlaybackStatus', 'public final class MediaPlayer {')),
    ('__STATE__', section(source, 'public enum APState', 'public struct APResource')),
    ('__TOGGLE__', section(source, '    public func playOrPause() -> Bool {', '    public func playOrPause(_ id: APSingleWrapper)')),
    ('__RESUME__', section(source, '    public func play() -> Bool {', '    @discardableResult public func next()')),
    ('__PLAY__', section(source, '    fileprivate func play(with item:', '    public var currentTime:')),
    ('__STOP__', section(source, '    public func stop() {', '    @discardableResult public func set(trackProgress:')),
    ('__TIMEBASE__', section(source, '    public func audioPlayerDidChangedTimebase(', '    public func stop()')),
    ('__TIMER__', section(source, '    private func startTimer()', '    deinit {')),
    ('__VOICE__', section(source[source.index('public class APChatVoiceController'):], '    public override func play(with item:', '    fileprivate override var tags:')),
]:
    fixture = fixture.replace(key, value.replace('public ', '').replace('fileprivate ', '').replace('private ', '').replace('SwiftSignalKit.Timer', 'ManualTimer').replace('RangeSet<Int64>', 'Int'))
with tempfile.TemporaryDirectory(prefix='audio-playback-session-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "PlaybackSession", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '+dependency+')], targets: [.testTarget(name: "PlaybackTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PlaybackTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
