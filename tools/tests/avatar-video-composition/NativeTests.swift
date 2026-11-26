import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import SwiftSignalKit
import XCTest

final class Window {}
protocol AccountContextProtocol:AnyObject {var window:Window {get}}
final class Context:AccountContextProtocol {let window=Window()}
__STATE__
final class VideoAvatarModalController {
 let asset:AVComposition,track:AVAssetTrack;let holder:AVAsset;let quality:String;static var shown:[VideoAvatarModalController]=[]
 init(context:any AccountContextProtocol,asset:AVComposition,track:AVAssetTrack,localize:String,quality:String,holder:AVAsset,confirm:((Signal<URL,NoError>,@escaping()->Void)->Void)?) {self.asset=asset;self.track=track;self.holder=holder;self.quality=quality}
 var completeState:Signal<VideoAvatarGeneratorState,NoError> {.single(.progress(0))}
}
func showModal(with controller:VideoAvatarModalController,for window:Window) {VideoAvatarModalController.shown.append(controller)}
__SELECTION__
class NativeFixture:XCTestCase {
 var paths:[String]=[]
 override func setUp() {VideoAvatarModalController.shown=[]}
 override func tearDown() {VideoAvatarModalController.shown=[];for path in paths {try? FileManager.default.removeItem(atPath:path)}}
 func source()->String {
  let writer=try! AvatarVideoExport(codec:AVVideoCodecType.h264.rawValue);var pixel:CVPixelBuffer?;XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,640,640,kCVPixelFormatType_32ARGB,nil,&pixel),kCVReturnSuccess);let buffer=pixel!;CVPixelBufferLockBaseAddress(buffer,[]);let c=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:640,height:640,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!;for (x,y,r,g,b):(Int,Int,CGFloat,CGFloat,CGFloat) in [(0,0,1,0,0),(320,0,0,1,0),(0,320,0,0,1),(320,320,1,1,0)] {c.setFillColor(red:r,green:g,blue:b,alpha:1);c.fill(CGRect(x:x,y:y,width:320,height:320))};CVPixelBufferUnlockBaseAddress(buffer,[])
  let done=expectation(description:"source");var output:String?;var frame=0;let queue=DispatchQueue(label:"avatar-composition-source");queue.async {writer.start(queue:queue,isCancelled:{false},next:{if frame==3 {return .finished(CMTime(value:3,timescale:30))};defer {frame+=1};return .frame(buffer,CMTime(value:Int64(frame),timescale:30))},completed:{output=$0;done.fulfill()})};wait(for:[done],timeout:15);let path=output!;paths.append(path);return path
 }
 func prepared(_ transform:CGAffineTransform = .identity,id:CMPersistentTrackID=42) throws -> (AVMutableComposition,AVMutableCompositionTrack) {let asset=AVURLAsset(url:URL(fileURLWithPath:source()));let original=try XCTUnwrap(asset.tracks(withMediaType:.video).first);let input=AVMutableComposition();let track=try XCTUnwrap(input.addMutableTrack(withMediaType:.video,preferredTrackID:id));try track.insertTimeRange(CMTimeRange(start:.zero,duration:asset.duration),of:original,at:.zero);track.preferredTransform=transform;let result=try XCTUnwrap(prepareEditedAvatarVideo(input));return(result.composition,result.track)}
 func rendered(_ transform:CGAffineTransform)->CGImage? {do {let (asset,track)=try prepared(transform);let video=try XCTUnwrap(editedAvatarVideoComposition(track:track,duration:asset.duration,selection:CGRect(x:0,y:0,width:640,height:640),viewSize:CGSize(width:640,height:640)));let generator=AVAssetImageGenerator(asset:asset);generator.videoComposition=video;return try generator.copyCGImage(at:.zero,actualTime:nil)} catch {XCTFail("Render failed: \(error)");return nil}}
 func pixel(_ image:CGImage,_ x:Int,_ y:Int)->[Int] {let c=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));let data=c.data!.assumingMemoryBound(to:UInt8.self);let start=y*c.bytesPerRow+x*4;return (0..<3).map {Int(data[start+$0])}}
 func similar(_ lhs:[Int],_ rhs:[Int],file:StaticString=#filePath,line:UInt=#line) {for i in 0..<3 {XCTAssertLessThan(abs(lhs[i]-rhs[i]),20,file:file,line:line)}}
}
final class PreparationTests:NativeFixture {
 func testCopiedTrackBelongsToNewCompositionAndHasNewIdentity() throws {let (asset,track)=try prepared();XCTAssertNotEqual(track.trackID,42);XCTAssertTrue(asset.tracks(withMediaType:.video).first === track);let video=try XCTUnwrap(editedAvatarVideoComposition(track:track,duration:asset.duration));let instruction=try XCTUnwrap(video.instructions.first as? AVVideoCompositionInstruction);XCTAssertEqual(instruction.layerInstructions.first?.trackID,track.trackID);let generator=AVAssetImageGenerator(asset:asset);generator.videoComposition=video;XCTAssertNoThrow(try generator.copyCGImage(at:.zero,actualTime:nil))}
 func testCopiedTrackPreservesPreferredTransform() throws {let t=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:640,ty:0);let (_,track)=try prepared(t);XCTAssertEqual(track.preferredTransform,t)}
 func testEmptyAssetCannotCreateEditorComposition() {XCTAssertNil(prepareEditedAvatarVideo(AVMutableComposition()))}
 func testInvalidDurationCannotCreateInstructions() throws {let (_,track)=try prepared();XCTAssertNil(editedAvatarVideoComposition(track:track,duration:.zero));XCTAssertNil(editedAvatarVideoComposition(track:track,duration:.indefinite))}
 func testMirroredCropExportsReadableVideoWithMatchingPixels() throws {let (asset,track)=try prepared(CGAffineTransform(a:-1,b:0,c:0,d:1,tx:640,ty:0));let video=try XCTUnwrap(editedAvatarVideoComposition(track:track,duration:asset.duration,selection:CGRect(x:160,y:160,width:320,height:320),viewSize:CGSize(width:640,height:640)));let preview=AVAssetImageGenerator(asset:asset);preview.videoComposition=video;let expected=try preview.copyCGImage(at:.zero,actualTime:nil);let done=expectation(description:"export");var result:String?;var failed=false;let d=generateEditedAvatarVideo(asset,composition:video,quality:AVAssetExportPresetHighestQuality,leftTrim:0,rightTrim:1,keyFrame:nil).start(next:{state in switch state {case let .complete(thumb,path,_):self.paths += [thumb,path];result=path;case .error:failed=true;default:break}},completed:{done.fulfill()});wait(for:[done],timeout:20);d.dispose();XCTAssertFalse(failed);let output=AVURLAsset(url:URL(fileURLWithPath:try XCTUnwrap(result)));XCTAssertEqual(output.tracks(withMediaType:.video).first?.naturalSize,CGSize(width:320,height:320));let actual=try AVAssetImageGenerator(asset:output).copyCGImage(at:.zero,actualTime:nil);similar(pixel(actual,32,32),pixel(expected,32,32));similar(pixel(actual,288,288),pixel(expected,288,288))}

}
final class NativeCropTests:NativeFixture {
 func testHorizontalMirrorMatchesOppositeSourceQuadrant() throws {let plain=try XCTUnwrap(rendered(.identity)),mirrored=try XCTUnwrap(rendered(CGAffineTransform(a:-1,b:0,c:0,d:1,tx:640,ty:0)));similar(pixel(mirrored,64,64),pixel(plain,576,64));similar(pixel(mirrored,576,576),pixel(plain,64,576))}
 func testVerticalMirrorMatchesOppositeSourceQuadrant() throws {let plain=try XCTUnwrap(rendered(.identity)),mirrored=try XCTUnwrap(rendered(CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:640)));similar(pixel(mirrored,64,64),pixel(plain,64,576));similar(pixel(mirrored,576,576),pixel(plain,576,64));similar(pixel(mirrored,576,64),pixel(plain,576,576));similar(pixel(mirrored,64,576),pixel(plain,64,64))}
 func testRotationMapsSourcePixels() throws {let plain=try XCTUnwrap(rendered(.identity)),rotated=try XCTUnwrap(rendered(CGAffineTransform(a:0,b:1,c:-1,d:0,tx:640,ty:0)));similar(pixel(rotated,64,64),pixel(plain,64,576));similar(pixel(rotated,576,64),pixel(plain,64,64))}
}
final class SelectionTests:NativeFixture {
 func testModalReceivesTrackFromPreparedComposition() throws {var values:[VideoAvatarGeneratorState]=[];selectVideoAvatar(context:Context(),path:source(),localize:"test",signal:{_=$0.start(next:{values.append($0)})});let controller=try XCTUnwrap(VideoAvatarModalController.shown.first);XCTAssertTrue(controller.asset.tracks(withMediaType:.video).first === controller.track);XCTAssertEqual(values,[.progress(0)])}
 func testMissingVideoReportsTerminalErrorWithoutModal() {var values:[VideoAvatarGeneratorState]=[];selectVideoAvatar(context:Context(),path:"/nonexistent/avatar.mp4",localize:"test",signal:{_=$0.start(next:{values.append($0)})});XCTAssertEqual(values,[.error]);XCTAssertTrue(VideoAvatarModalController.shown.isEmpty)}
 func testInvalidVideoReportsTerminalErrorWithoutModal() throws {let path=NSTemporaryDirectory()+UUID().uuidString+".mp4";paths.append(path);try Data([1,2,3]).write(to:URL(fileURLWithPath:path));var values:[VideoAvatarGeneratorState]=[];selectVideoAvatar(context:Context(),path:path,localize:"test",signal:{_=$0.start(next:{values.append($0)})});XCTAssertEqual(values,[.error]);XCTAssertTrue(VideoAvatarModalController.shown.isEmpty)}
 func testRequestedQualityIsPreserved() {selectVideoAvatar(context:Context(),path:source(),localize:"test",quality:AVAssetExportPresetHighestQuality,signal:{_ in});XCTAssertEqual(VideoAvatarModalController.shown.first?.quality,AVAssetExportPresetHighestQuality)}
}
