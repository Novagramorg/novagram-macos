import Foundation
import AVFoundation
import CoreVideo
import XCTest

final class NativeTests:XCTestCase {
    var paths:[String]=[]
    override func tearDown(){for path in paths{try? FileManager.default.removeItem(atPath:path)}}
    func source(seconds:Int=1)throws->URL {
        let writer=try AvatarVideoExport(codec:AVVideoCodecType.h264.rawValue)
        var pixel:CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,640,640,kCVPixelFormatType_32ARGB,nil,&pixel),kCVReturnSuccess)
        let buffer=try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer,[])
        if let address=CVPixelBufferGetBaseAddress(buffer){memset(address,255,CVPixelBufferGetDataSize(buffer))}
        CVPixelBufferUnlockBaseAddress(buffer,[])
        let queue=DispatchQueue(label:"recording-composition-source")
        let done=expectation(description:"source")
        var path:String?,frame=0
        queue.async{writer.start(queue:queue,isCancelled:{false},next:{if frame==seconds*30{return .finished(CMTime(value:Int64(frame),timescale:30))};defer{frame+=1};return .frame(buffer,CMTime(value:Int64(frame),timescale:30))},completed:{path=$0;done.fulfill()})}
        wait(for:[done],timeout:20)
        let output=try XCTUnwrap(path);paths.append(output);return URL(fileURLWithPath:output)
    }
    func testEmptyListHasNoComposition(){XCTAssertNil(recordingVideoComposition([]))}
    func testMissingSegmentRejectsWholeJoin()throws{let valid=try source();XCTAssertNil(recordingVideoComposition([valid,URL(fileURLWithPath:"/missing-recording.mp4")]))}
    func testCorruptSegmentRejectsWholeJoin()throws{let valid=try source();let corrupt=NSTemporaryDirectory()+UUID().uuidString+".mp4";paths.append(corrupt);try Data([1,2,3]).write(to:URL(fileURLWithPath:corrupt));XCTAssertNil(recordingVideoComposition([valid,URL(fileURLWithPath:corrupt)]))}
    func testSingleNativeAssetDurationIsMeasured()throws{let source=try source(seconds:2);XCTAssertEqual(try XCTUnwrap(recordingVideoDuration(AVURLAsset(url:source))),2,accuracy:0.01)}
    func testJoinedNativeSegmentsRetainEntireTimelineAndExport()throws{
        let first=try source(),second=try source(seconds:2)
        let composition=try XCTUnwrap(recordingVideoComposition([first,second]))
        XCTAssertEqual(composition.duration.seconds,3,accuracy:0.01)
        XCTAssertEqual(composition.tracks(withMediaType:.video).first?.segments.count,2)
        let output=NSTemporaryDirectory()+UUID().uuidString+".mp4";paths.append(output)
        let exporter=try XCTUnwrap(AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetPassthrough))
        exporter.outputURL=URL(fileURLWithPath:output);exporter.outputFileType = .mp4
        let done=expectation(description:"join export");exporter.exportAsynchronously{done.fulfill()};wait(for:[done],timeout:20)
        XCTAssertEqual(exporter.status,.completed)
        let asset=AVURLAsset(url:URL(fileURLWithPath:output))
        XCTAssertEqual(try XCTUnwrap(recordingVideoDuration(asset)),3,accuracy:0.05)
        let generator=AVAssetImageGenerator(asset:asset)
        XCTAssertNoThrow(try generator.copyCGImage(at:CMTime(seconds:0.5,preferredTimescale:1000),actualTime:nil))
        XCTAssertNoThrow(try generator.copyCGImage(at:CMTime(seconds:2.5,preferredTimescale:1000),actualTime:nil))
    }
    func testEmptyNativeAssetIsRejected(){XCTAssertNil(recordingVideoDuration(AVMutableComposition()))}
}
