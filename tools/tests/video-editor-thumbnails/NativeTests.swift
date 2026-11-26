import Cocoa
import AVFoundation
import CoreVideo
import SwiftSignalKit
import XCTest

final class NativeTests: XCTestCase {
    var paths: [String] = []
    override func tearDown() { for path in paths { try? FileManager.default.removeItem(atPath: path) } }
    func source() throws -> AVMutableComposition {
        let writer = try AvatarVideoExport(codec: AVVideoCodecType.h264.rawValue)
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 640, 640, kCVPixelFormatType_32ARGB, nil, &pixel), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let address = CVPixelBufferGetBaseAddress(buffer) { memset(address, 255, CVPixelBufferGetDataSize(buffer)) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let queue = DispatchQueue(label: "thumbnail-source")
        let done = expectation(description: "source")
        var path: String?, frame = 0
        queue.async {
            writer.start(queue: queue, isCancelled: { false }, next: {
                if frame == 30 { return .finished(CMTime(seconds: 1, preferredTimescale: 30)) }
                defer { frame += 1 }
                return .frame(buffer, CMTime(value: Int64(frame), timescale: 30))
            }, completed: { path = $0; done.fulfill() })
        }
        wait(for: [done], timeout: 20)
        let output = try XCTUnwrap(path); paths.append(output)
        let asset = AVURLAsset(url: URL(fileURLWithPath: output)), result = AVMutableComposition()
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let copied = try XCTUnwrap(result.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try copied.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: track, at: .zero)
        return result
    }
    func testNativeStripProducesAllFramesAndCompletes() throws {
        let asset = try source(), done = expectation(description: "strip")
        var final: [CGImage] = []
        let d = generateVideoScrubberThumbs(for: asset, composition: nil, size: CGSize(width: 40, height: 20), count: 4, gradually: true, blur: true).start(next: { if $0.1 { final = $0.0 } }, completed: { done.fulfill() })
        defer { d.dispose() }; wait(for: [done], timeout: 5)
        XCTAssertEqual(final.count, 4)
        XCTAssertTrue(final.allSatisfy { $0.width <= 80 && $0.height <= 40 })
    }
    func testNativePreviewHonorsLowResolutionSize() throws {
        let asset = try source(), done = expectation(description: "preview")
        var result: (CGImage?, CGImage?)?
        let d = generateVideoAvatarPreview(for: asset, composition: nil, highSize: CGSize(width: 80, height: 80), lowSize: CGSize(width: 10, height: 10), at: 0.5).start(next: { result = $0 }, completed: { done.fulfill() })
        defer { d.dispose() }; wait(for: [done], timeout: 5)
        XCTAssertEqual(result?.0?.width, 160)
        XCTAssertEqual(result?.1?.width, 20)
        XCTAssertEqual(result?.1?.height, 20)
    }
    func testNativePreviewUsesVideoCompositionGeometry() throws {
        let asset = try source(), done = expectation(description: "composed preview")
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: 320, height: 160)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: try XCTUnwrap(asset.tracks(withMediaType: .video).first))
        layer.setTransform(CGAffineTransform(scaleX: 0.5, y: 0.25), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        instruction.layerInstructions = [layer]; composition.instructions = [instruction]
        var result: (CGImage?, CGImage?)?
        let d = generateVideoAvatarPreview(for: asset, composition: composition, highSize: CGSize(width: 80, height: 80), lowSize: CGSize(width: 10, height: 10), at: 0.5).start(next: { result = $0 }, completed: { done.fulfill() })
        defer { d.dispose() }; wait(for: [done], timeout: 5)
        XCTAssertEqual(result?.0?.width, 160); XCTAssertEqual(result?.0?.height, 80)
        XCTAssertEqual(result?.1?.width, 20); XCTAssertEqual(result?.1?.height, 10)
    }
    func testNativeEmptyCompositionTerminates() {
        let done = expectation(description: "empty asset")
        var result: ([CGImage], Bool)?
        let d = generateVideoScrubberThumbs(for: AVMutableComposition(), composition: nil, size: CGSize(width: 40, height: 20), count: 3, gradually: true, blur: false).start(next: { result = $0 }, completed: { done.fulfill() })
        defer { d.dispose() }; wait(for: [done], timeout: 1)
        XCTAssertEqual(result?.1, true); XCTAssertEqual(result?.0.count, 0)
    }
    func testNativePreviewPastEndFailsAndCompletes() throws {
        let asset = try source(), done = expectation(description: "invalid frame")
        var received = false
        let d = generateVideoAvatarPreview(for: asset, composition: nil, highSize: CGSize(width: 80, height: 80), lowSize: CGSize(width: 10, height: 10), at: 2).start(next: { received = true; XCTAssertNil($0.0); XCTAssertNil($0.1) }, completed: { done.fulfill() })
        defer { d.dispose() }; wait(for: [done], timeout: 5); XCTAssertTrue(received)
    }
    func testNativeGappedAssetStillTerminates() throws {
        let asset = try source()
        asset.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 30)))
        let done = expectation(description: "gapped asset")
        var result: ([CGImage], Bool)?
        let d = generateVideoScrubberThumbs(for: asset, composition: nil, size: CGSize(width: 40, height: 20), count: 4, gradually: true, blur: true).start(next: { result = $0 }, completed: { done.fulfill() })
        defer { d.dispose() }; wait(for: [done], timeout: 3)
        XCTAssertEqual(result?.1, true)
    }
}
