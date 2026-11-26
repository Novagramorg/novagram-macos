import Foundation
import CoreGraphics
import ImageIO
import CoreServices
import SwiftSignalKit
import XCTest

var unsafeBaseline=false
struct TransformImageArguments {}
struct ImageRenderData {let fullSizeData:Data?;let fullSizeComplete:Bool}
final class DrawingContext {let image:CGImage?;init(_ image:CGImage?) {self.image=image};func generateImage()->CGImage? {image}}
struct ImageDataTransformation {let data:ImageRenderData;let execute:(TransformImageArguments,ImageRenderData)->DrawingContext?}
__PATTERN__
final class PatternTests:XCTestCase {
 func image()->CGImage {CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!}
 func png()->Data {let data=NSMutableData();let destination=CGImageDestinationCreateWithData(data,kUTTypePNG,1,nil)!;CGImageDestinationAddImage(destination,image(),nil);XCTAssertTrue(CGImageDestinationFinalize(destination));return data as Data}
 func value(_ complete:Bool,data:Data?=nil,rendered:CGImage?=nil,onDraw:(()->Void)?=nil)->ImageDataTransformation {.init(data:.init(fullSizeData:data,fullSizeComplete:complete),execute:{_,_ in onDraw?();return DrawingContext(rendered ?? self.image())})}
 func testLoadingPlaceholderIsNotDrawnOrAccepted() {let source=ValuePipe<ImageDataTransformation>();var count=0,draws=0;let d=avatarPatternBackground(source.signal(),arguments:.init()).start(next:{_ in count+=1});source.putNext(value(false,onDraw:{draws+=1}));XCTAssertEqual(count,0);XCTAssertEqual(draws,0);source.putNext(value(true,data:png(),onDraw:{draws+=1}));XCTAssertEqual(count,1);XCTAssertEqual(draws,1);d.dispose()}
 func testOnlyFirstCompletePatternIsUsed() {let source=ValuePipe<ImageDataTransformation>();var count=0,completed=0;let d=avatarPatternBackground(source.signal(),arguments:.init()).start(next:{_ in count+=1},completed:{completed+=1});source.putNext(value(true,data:png()));source.putNext(value(true,data:png()));XCTAssertEqual(count,1);XCTAssertEqual(completed,1);d.dispose()}
 func testMissingCompleteDataDoesNotProduceFakeBackground() {var count=0,completed=0;let d=avatarPatternBackground(.single(value(true)),arguments:.init()).start(next:{_ in count+=1},completed:{completed+=1});XCTAssertEqual(count,0);XCTAssertEqual(completed,1);d.dispose()}
 func testInvalidCompleteDataDoesNotProduceFakeBackground() {var count=0,draws=0;let d=avatarPatternBackground(.single(value(true,data:Data([1,2,3]),onDraw:{draws+=1})),arguments:.init()).start(next:{_ in count+=1});XCTAssertEqual(count,0);XCTAssertEqual(draws,0);d.dispose()}
 func testNilDrawingContextCompletesWithoutImage() throws {if unsafeBaseline {throw XCTSkip("Original force unwrap traps")};let v=ImageDataTransformation(data:.init(fullSizeData:png(),fullSizeComplete:true),execute:{_,_ in nil});var count=0,completed=0;let d=avatarPatternBackground(.single(v),arguments:.init()).start(next:{_ in count+=1},completed:{completed+=1});XCTAssertEqual(count,0);XCTAssertEqual(completed,1);d.dispose()}
 func testNilExtractedImageCompletesWithoutImage() throws {if unsafeBaseline {throw XCTSkip("Original force unwrap traps")};let v=ImageDataTransformation(data:.init(fullSizeData:png(),fullSizeComplete:true),execute:{_,_ in DrawingContext(nil)});var count=0;let d=avatarPatternBackground(.single(v),arguments:.init()).start(next:{_ in count+=1});XCTAssertEqual(count,0);d.dispose()}
 func testCancellationSuppressesLatePattern() {let source=ValuePipe<ImageDataTransformation>();var count=0;let d=avatarPatternBackground(source.signal(),arguments:.init()).start(next:{_ in count+=1});d.dispose();source.putNext(value(true,data:png()));XCTAssertEqual(count,0)}
 func testValidPatternImageIsForwarded() {let expected=image();var actual:CGImage?;let d=avatarPatternBackground(.single(value(true,data:png(),rendered:expected)),arguments:.init()).start(next:{actual=$0});XCTAssertTrue(actual === expected);d.dispose()}
 func testEmptySourceCompletesWithoutImage() {var count=0,completed=0;let d=avatarPatternBackground(.complete(),arguments:.init()).start(next:{_ in count+=1},completed:{completed+=1});XCTAssertEqual(count,0);XCTAssertEqual(completed,1);d.dispose()}
 func testPlaceholderOnlySourceCompletesWithoutImage() {var count=0,completed=0;let d=avatarPatternBackground(.single(value(false)),arguments:.init()).start(next:{_ in count+=1},completed:{completed+=1});XCTAssertEqual(count,0);XCTAssertEqual(completed,1);d.dispose()}
 func testAcceptedPatternDisposesUpstreamImmediately() {var subscriber:Subscriber<ImageDataTransformation,NoError>?;var disposed=0;let source=Signal<ImageDataTransformation,NoError> {value in subscriber=value;return ActionDisposable {disposed+=1}};let d=avatarPatternBackground(source,arguments:.init()).start();subscriber?.putNext(value(true,data:png()));XCTAssertEqual(disposed,1);d.dispose();XCTAssertEqual(disposed,1)}

}
