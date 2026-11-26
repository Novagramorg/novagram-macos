from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = root / 'packages/ChatUI/Sources/ChatUI/ChatInteractiveContentView.swift'
source = path.read_text()
pairs = [('    private func updateMediaStatus(', '    public override func interactionControllerDidFinishAnimation'), ('    @objc public func updatePlayerIfNeeded()', '    private func updateLivePhoto('), ('    private func removeLivePhotoPlayer()', '    private func removeLivePhoto()')]
methods = '\n'.join(source[source.index(a):source.index(b, source.index(a))] for a, b in pairs)
protocol = source[source.index('public protocol ChatVideoAutoplayPlayer:'):source.index('extension MediaPlayer:')]
timer = source[source.index('fileprivate final class ChatVideoAccessoryTimer'):source.index('public final class ChatVideoAutoplayView')]
timer = timer.replace('class ChatVideoAccessoryTimer {', 'class ChatVideoAccessoryTimer: LabPlaybackTimer {')
timer = timer.replace('private var source: DispatchSourceTimer?', 'private var source: LabDispatchTimer?\n    private var storedRecord: TimerRecord?\n    var record: TimerRecord { storedRecord! }\n    func start() {}\n    func fire() { source?.fire() }')
timer = timer.replace('DispatchSource.makeTimerSource', 'LabDispatchTimer.makeTimerSource').replace('self.source = source', 'self.source = source\n        self.storedRecord = source.record')
wrapper = source[source.index('public final class ChatVideoAutoplayView'):source.index('private final class VideoTimestampView')].replace('playTimer: ChatVideoAccessoryTimer?', 'playTimer: LabPlaybackTimer?')
reference = (lab / 'Reference.swift.txt').read_text()
output = 'import Cocoa\nimport SwiftSignalKit\n\n' + protocol + timer + wrapper
for name, body in [('CurrentMediaView', methods), ('ReferenceMediaView', reference)]:
    body = body.replace('private func ', 'override func ').replace('@objc public func updatePlayerIfNeeded', 'override func updatePlayerIfNeeded')
    output += '\nclass ' + name + ': MediaEnvironment {\n' + body + '}\n'
output = output.replace('public ', '').replace('fileprivate ', '').replace('SwiftSignalKit.Timer', 'LabTimer')
(lab / 'Sources/Playback/Generated.swift').write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': 'fd83dc917', 'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
