import Foundation
import AVFoundation
import CoreVideo
import XCTest
import SwiftSignalKit

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
    func exported(_ signal: Signal<RecordingVideoExportResult?, NoError>) -> RecordingVideoExportResult? {
        let done=expectation(description:"export")
        var result:RecordingVideoExportResult?
        let d=signal.start(next:{result=$0},completed:{done.fulfill()})
        wait(for:[done],timeout:20)
        d.dispose()
        return result
    }
    func testRealTrimReportsReadableActualDuration() throws {
        let source=try source()
        let result=try XCTUnwrap(exported(exportTrimmedVideo(path:source.path,range:0.2..<0.8)))
        XCTAssertEqual(result.duration,0.6,accuracy:0.05)
        let output=try XCTUnwrap(result.takePath());paths.append(output)
        let asset=AVURLAsset(url:URL(fileURLWithPath:output))
        XCTAssertEqual(asset.duration.seconds,result.duration,accuracy:0.001)
        XCTAssertNoThrow(try AVAssetImageGenerator(asset:asset).copyCGImage(at:CMTime(seconds:0.3,preferredTimescale:1000),actualTime:nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
    func testRealJoinedExportRetainsBothSegments() throws {
        let first=try source(),second=try source(seconds:2)
        let composition=try XCTUnwrap(recordingVideoComposition([first,second]))
        let result=try XCTUnwrap(exported(passthroughExport(asset:composition,name:"joined")))
        XCTAssertEqual(result.duration,3,accuracy:0.05)
        let path=try XCTUnwrap(result.takePath());paths.append(path)
        XCTAssertNoThrow(try AVAssetImageGenerator(asset:AVURLAsset(url:URL(fileURLWithPath:path))).copyCGImage(at:CMTime(seconds:2.5,preferredTimescale:1000),actualTime:nil))
    }
    func testNativeUnclaimedResultDeletesFile() throws {
        let source=try source()
        var result=exported(exportTrimmedVideo(path:source.path,range:0.2..<0.8))
        let path=try XCTUnwrap(result?.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath:path))
        result=nil
        XCTAssertFalse(FileManager.default.fileExists(atPath:path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
    func testMissingInputFailsWithoutOutput(){XCTAssertNil(exported(exportTrimmedVideo(path:"/missing-recording.mp4",range:0..<1)))}
    func testOutOfBoundsNativeTrimFails() throws {let source=try source();XCTAssertNil(exported(exportTrimmedVideo(path:source.path,range:0..<2)));XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))}
    func testEmptyCompositionFails(){XCTAssertNil(exported(passthroughExport(asset:AVMutableComposition(),name:"empty")))}
}
