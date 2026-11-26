import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(); parser.add_argument('--baseline', action='store_true'); args = parser.parse_args()
recording = (Path('/tmp/RecordingTrimScrubberView-before-thumbnail-lifetime.swift') if args.baseline else root/'packages/ChatUI/Sources/ChatUI/RecordingTrimScrubberView.swift').read_text()
editor = (Path('/tmp/EditVideoController-before-thumbnail-lifetime.swift') if args.baseline else root/'packages/ImageCanvasUI/Sources/ImageCanvasUI/EditVideoController.swift').read_text()
def block(source, marker):
    a=source.index(marker); b=source.index('{', a)+1; depth=1
    while depth:
        depth+=(source[b]=='{')-(source[b]=='}'); b+=1
    return source[a:b]
recordingBody = recording[recording.index('public final class RecordingTrimScrubberView'):]
markers = ['    public func setVideo(', '    private func updateThumbnails(', '    public func update(duration:']
if not args.baseline: markers += ['    private func invalidateThumbnails(', '    public override func viewDidMoveToWindow()']
recordingMethods = '\n'.join(block(recordingBody, marker).replace('public ', '').replace('private ', '') for marker in markers)
editorMethods = '\n'.join(block(editor, marker).replace('public ', '').replace('private ', '') for marker in ['    private func updateThumbnailsIfNeeded()', '    public override func viewWillDisappear(', '    public override func viewDidAppear(', '    private func play()', '    private func togglePlay()', '    private func handlePlaybackEnd()'])
layout = block(recording[recording.index('private final class TrimThumbnailsView'):], '    public override func layout()').replace('public ', '')
fixture = Path(__file__).with_name('ThumbnailCallerTests.swift').read_text().replace('__RECORDING__', recordingMethods).replace('__EDITOR__', editorMethods).replace('__LAYOUT__', layout)
fixture = (root/'packages/ChatUI/Sources/ChatUI/RecordingTrimState.swift').read_text() + '\n' + fixture
fixture = fixture.replace('__REQUEST__', '(path: String, count: Int)?' if args.baseline else '(path: String, count: Int, size: NSSize)?')
fixture = fixture.replace('__END_SEEK__', block(editor, '        scrubber.onEndSeeking =').split(' = ', 1)[1])
a = editor.index('        timeObserver = player.addPeriodicTimeObserver('); b = editor.index('{ [weak self]', a)
fixture = fixture.replace('__TICK__', block(editor[b:], '{ [weak self]'))
with tempfile.TemporaryDirectory(prefix='video-thumbnail-callers-') as directory:
    directory = Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "VideoThumbnailCallers", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')], targets: [.testTarget(name: "CallerTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/ThumbnailCallerTests.swift').write_text(fixture)
    import os
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4'], env=dict(os.environ, CALLER_BASELINE='1' if args.baseline else '0')).returncode)
