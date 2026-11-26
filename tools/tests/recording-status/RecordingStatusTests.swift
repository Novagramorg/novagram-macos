import Cocoa
import SwiftSignalKit
import XCTest

public struct AudioWaveform: Equatable { let samples: [Int] }
__SOURCE__

final class RecordingStatusTests: XCTestCase {
    func image() -> CGImage {
        CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    func preview(_ path:String="original.mp4",_ duration:Double=10,waveform:AudioWaveform?=nil,thumb:CGImage?=nil) -> ChatRecordingPreviewData {
        ChatRecordingPreviewData(path:path,duration:duration,waveform:waveform,thumb:thumb)
    }
    func updates(_ states:[VideoCameraRecordingStatus]) -> [VideoCameraRecordingStatus] {
        let promise=ValuePromise<VideoCameraRecordingStatus>(ignoreRepeated:true)
        var values:[VideoCameraRecordingStatus]=[]
        let d=promise.get().start(next:{values.append($0)})
        for state in states {promise.set(state)}
        d.dispose()
        return values
    }
    func testPausedNewPathPublishes() {XCTAssertEqual(updates([.paused(info:preview()),.paused(info:preview("trimmed.mp4"))]).count,2)}
    func testPausedNewDurationPublishes() {XCTAssertEqual(updates([.paused(info:preview()),.paused(info:preview("original.mp4",6))]).count,2)}
    func testPausedNewWaveformPublishes() {XCTAssertEqual(updates([.paused(info:preview(waveform:AudioWaveform(samples:[1]))),.paused(info:preview(waveform:AudioWaveform(samples:[2])))]).count,2)}
    func testPausedNewThumbnailPublishes() {XCTAssertEqual(updates([.paused(info:preview(thumb:image())),.paused(info:preview(thumb:image()))]).count,2)}
    func testPausedRemovedThumbnailPublishes() {XCTAssertEqual(updates([.paused(info:preview(thumb:image())),.paused(info:preview())]).count,2)}
    func testPausedUnchangedSnapshotIsSuppressed() {let p=preview(waveform:AudioWaveform(samples:[1]),thumb:image());XCTAssertEqual(updates([.paused(info:p),.paused(info:p)]).count,1)}
    func testPausedEquivalentWaveformIsSuppressed() {XCTAssertEqual(updates([.paused(info:preview(waveform:AudioWaveform(samples:[1]))),.paused(info:preview(waveform:AudioWaveform(samples:[1])))]).count,1)}
    func testFinishedNewPathPublishes() {XCTAssertEqual(updates([.finishRecording(path:"a",duration:10,id:1,thumb:nil),.finishRecording(path:"b",duration:10,id:1,thumb:nil)]).count,2)}
    func testFinishedNewDurationPublishes() {XCTAssertEqual(updates([.finishRecording(path:"a",duration:10,id:1,thumb:nil),.finishRecording(path:"a",duration:6,id:1,thumb:nil)]).count,2)}
    func testFinishedNewUploadIdentityPublishes() {XCTAssertEqual(updates([.finishRecording(path:"a",duration:10,id:1,thumb:nil),.finishRecording(path:"a",duration:10,id:2,thumb:nil)]).count,2)}
    func testFinishedRemovedUploadIdentityPublishes() {XCTAssertEqual(updates([.finishRecording(path:"a",duration:10,id:1,thumb:nil),.finishRecording(path:"a",duration:10,id:nil,thumb:nil)]).count,2)}
    func testFinishedNewThumbnailPublishes() {XCTAssertEqual(updates([.finishRecording(path:"a",duration:10,id:nil,thumb:image()),.finishRecording(path:"a",duration:10,id:nil,thumb:image())]).count,2)}
    func testFinishedUnchangedSnapshotIsSuppressed() {let state=VideoCameraRecordingStatus.finishRecording(path:"a",duration:10,id:1,thumb:image());XCTAssertEqual(updates([state,state]).count,1)}
    func testMadeThumbnailReplacementPublishes() {XCTAssertEqual(updates([.madeThumbnail(image()),.madeThumbnail(image())]).count,2)}
    func testMadeThumbnailSameImageIsSuppressed() {let image=image();XCTAssertEqual(updates([.madeThumbnail(image),.madeThumbnail(image)]).count,1)}
    func testStoppedThumbnailReplacementPublishes() {XCTAssertEqual(updates([.stopped(thumb:image()),.stopped(thumb:image())]).count,2)}
    func testStoppedThumbnailRemovalPublishes() {XCTAssertEqual(updates([.stopped(thumb:image()),.stopped(thumb:nil)]).count,2)}
    func testStoppedUnchangedSnapshotIsSuppressed() {let state=VideoCameraRecordingStatus.stopped(thumb:image());XCTAssertEqual(updates([state,state]).count,1)}
    func testDifferentCasesAreNeverEqual() {let states:[VideoCameraRecordingStatus]=[.idle,.startingRecording,.recording,.madeThumbnail(image()),.stoppingRecording,.paused(info:preview()),.stopped(thumb:nil),.failed,.finishRecording(path:"a",duration:1,id:nil,thumb:nil)];for (i,lhs) in states.enumerated(){for (j,rhs) in states.enumerated(){XCTAssertEqual(lhs==rhs,i==j)}}}
    func testPayloadFreeRepeatedCasesRemainSuppressed() {for state:VideoCameraRecordingStatus in [.idle,.startingRecording,.recording,.stoppingRecording,.failed]{XCTAssertEqual(updates([state,state]).count,1)}}
    func testPauseTrimResumePausePublishesFullSequence() {let values=updates([.recording,.paused(info:preview()),.paused(info:preview("trimmed.mp4",6)),.recording,.paused(info:preview("joined.mp4",8))]);XCTAssertEqual(values.count,5)}
    func testPausedInfoSubscriberReceivesTrimmedPathAndDuration() {let promise=ValuePromise<VideoCameraRecordingStatus>(ignoreRepeated:true);var previews:[ChatRecordingPreviewData]=[];let d=(promise.get() |> map { state -> ChatRecordingPreviewData? in if case let .paused(info)=state{return info};return nil }).start(next:{if let p=$0{previews.append(p)}});promise.set(.paused(info:preview()));promise.set(.paused(info:preview("trimmed.mp4",6)));XCTAssertEqual(previews.map(\.path),["original.mp4","trimmed.mp4"]);XCTAssertEqual(previews.map(\.duration),[10,6]);d.dispose()}
}
