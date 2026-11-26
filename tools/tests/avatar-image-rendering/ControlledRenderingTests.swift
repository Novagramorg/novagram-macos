import Foundation
import XCTest

typealias CFDictionary=[String:Bool]
let kCVPixelBufferCGImageCompatibilityKey="image",kCVPixelBufferCGBitmapContextCompatibilityKey="bitmap",kCFBooleanTrue=true,kCVPixelFormatType_32ARGB:Int32=1,kCVReturnSuccess:Int32=0
let kCFAllocatorDefault:Int?=nil
final class CGImage {let width:Int;let height:Int;init(_ width:Int=8,_ height:Int=8) {self.width=width;self.height=height}}
enum CGImageAlphaInfo:UInt32 {case premultipliedLast=1,noneSkipFirst=2}
func CGColorSpaceCreateDeviceRGB()->Int {1}
final class State {static var createError=false,missingBuffer=false,lockError=false,missingAddress=false,contextError=false,imageError=false;static var creates=0,locks=0,unlocks=0,contexts=0,draws=0,makes=0;static func reset() {createError=false;missingBuffer=false;lockError=false;missingAddress=false;contextError=false;imageError=false;creates=0;locks=0;unlocks=0;contexts=0;draws=0;makes=0}}
final class CVPixelBuffer {}
func CVPixelBufferCreate(_ allocator:Int?,_ width:Int,_ height:Int,_ format:Int32,_ attributes:CFDictionary,_ result:inout CVPixelBuffer?)->Int32 {State.creates+=1;result=State.missingBuffer ? nil:CVPixelBuffer();return State.createError ? -1:0}
func CVPixelBufferLockBaseAddress(_ buffer:CVPixelBuffer,_ flags:[Int])->Int32 {State.locks+=1;return State.lockError ? -1:0}
func CVPixelBufferUnlockBaseAddress(_ buffer:CVPixelBuffer,_ flags:[Int]) {State.unlocks+=1}
func CVPixelBufferGetBaseAddress(_ buffer:CVPixelBuffer)->UnsafeMutableRawPointer? {State.missingAddress ? nil:UnsafeMutableRawPointer(bitPattern:1)}
func CVPixelBufferGetBytesPerRow(_ buffer:CVPixelBuffer)->Int {32}
final class CGContext {
 let width:Int,height:Int
 init?(data:UnsafeMutableRawPointer?,width:Int,height:Int,bitsPerComponent:Int,bytesPerRow:Int,space:Int,bitmapInfo:UInt32) {State.contexts+=1;if State.contextError {return nil};self.width=width;self.height=height}
 func clear(_ rect:CGRect) {};func translateBy(x:CGFloat,y:CGFloat) {};func scaleBy(x:CGFloat,y:CGFloat) {};func draw(_ image:CGImage,in rect:CGRect) {State.draws+=1};func makeImage()->CGImage? {State.makes+=1;return State.imageError ? nil:CGImage(width,height)}
}
__RENDER__
final class ControlledRenderingTests:XCTestCase {
 override func setUp() {State.reset()}
 func testAllocationFailureDoesNotLockOrDraw() {State.createError=true;XCTAssertNil(avatarPixelBuffer(from:CGImage()));XCTAssertEqual(State.locks,0);XCTAssertEqual(State.draws,0)}
 func testSuccessfulStatusWithoutBufferDoesNotCrash() {State.missingBuffer=true;XCTAssertNil(avatarPixelBuffer(from:CGImage()));XCTAssertEqual(State.locks,0)}
 func testFailedLockDoesNotReadOrUnlock() {State.lockError=true;XCTAssertNil(avatarPixelBuffer(from:CGImage()));XCTAssertEqual(State.locks,1);XCTAssertEqual(State.unlocks,0);XCTAssertEqual(State.contexts,0)}
 func testMissingAddressUnlocksAndRejectsBuffer() {State.missingAddress=true;XCTAssertNil(avatarPixelBuffer(from:CGImage()));XCTAssertEqual(State.unlocks,1);XCTAssertEqual(State.contexts,0)}
 func testFailedContextUnlocksAndRejectsBuffer() {State.contextError=true;XCTAssertNil(avatarPixelBuffer(from:CGImage()));XCTAssertEqual(State.unlocks,1);XCTAssertEqual(State.draws,0)}
 func testSuccessfulBufferUnlocksExactlyOnce() {XCTAssertNotNil(avatarPixelBuffer(from:CGImage(),background:CGImage()));XCTAssertEqual(State.locks,1);XCTAssertEqual(State.unlocks,1);XCTAssertEqual(State.draws,2)}
 func testInvalidTransformFailsBeforeAllocation() {XCTAssertNil(avatarPixelBuffer(from:CGImage(),zoom:.nan));XCTAssertEqual(State.creates,0)}
 func testBitmapContextAllocationFailureIsNil() {State.contextError=true;XCTAssertNil(avatarCompositedImage(from:CGImage(),offset:.zero));XCTAssertEqual(State.draws,0)}
 func testImageExtractionFailureIsNil() {State.imageError=true;XCTAssertNil(avatarCompositedImage(from:CGImage(),offset:.zero));XCTAssertEqual(State.makes,1)}
 func testRejectedDrawingDoesNotExtractImage() {XCTAssertNil(avatarDrawingImage(size:CGSize(width:8,height:8)) {_,_ in false});XCTAssertEqual(State.makes,0)}
 func testIntegerOverflowDoesNotAllocateContext() {XCTAssertNil(avatarDrawingImage(size:CGSize(width:CGFloat(Int.max/2),height:8)) {_,_ in XCTFail();return true});XCTAssertEqual(State.contexts,0)}
 func testPixelCountOverflowDoesNotAllocateContext() {XCTAssertNil(avatarDrawingImage(size:CGSize(width:Double(1<<32),height:Double(1<<32))) {_,_ in XCTFail();return true});XCTAssertEqual(State.contexts,0)}
}
