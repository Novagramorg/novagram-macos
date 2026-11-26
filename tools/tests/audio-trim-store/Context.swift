import Foundation
import XCTest

let baseline = ProcessInfo.processInfo.environment["AUDIO_TRIM_BASELINE"] == "1"
let opusDecodedSampleRate = 48000
let opusFrameSamples = 960
__FUNCTIONS__
final class Queue { func isCurrent() -> Bool { true } }
enum AudioRecordingState { case paused(duration: Double) }
final class State { var values: [Double] = []; func set(_ state: AudioRecordingState) { if case let .paused(duration) = state { values.append(duration) } } }
final class Context {
    let queue = Queue(), recordingState = State()
    var dataItem: DataItem, oggWriter: TGOggOpusWriter
    var encoderState: [AnyHashable: Any]?
    var paused = true
    var liveUploading: Int? = 42
    var recordingStateUpdateTimestamp: Double? = 3
    var waveformTrims: [(Double, Double)] = []
    init(_ path: String) { dataItem = DataItem(path: path); oggWriter = TGOggOpusWriter() }
    func trimWaveformSamples(from start: Double, to end: Double) { waveformTrims.append((start,end)) }
    __METHODS__
}
class Case: XCTestCase {
    var directory: URL!
    var source: String { directory.appendingPathComponent("source.ogg").path }
    var output: String { directory.appendingPathComponent("output.ogg").path }
    override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func contents(_ path: String) -> Data? { try? Data(contentsOf: URL(fileURLWithPath: path)) }
}
