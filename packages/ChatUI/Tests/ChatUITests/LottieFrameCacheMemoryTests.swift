import XCTest
import AppKit
import SwiftSignalKit
import Compression
@testable import TelegramMedia

final class LottieFrameCacheMemoryTests: XCTestCase {

    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "trlottie-memory-\(UUID().uuidString)/"
        TRLotData.directoryOverride = directory
    }

    override func tearDown() {
        TRLotData.directoryOverride = nil
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func mallocInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return stats.size_in_use
    }

    private func makeSupplyment(_ name: String, side: CGFloat) -> (TRLotFileSupplyment, Int) {
        let key = LottieAnimationEntryKey(key: .bundle("memtest-\(name)-\(UUID().uuidString)"), size: CGSize(width: side, height: side), backingScale: 2)
        let animation = LottieAnimation(compressed: Data(), key: key)
        let bufferSize = animation.bufferSize
        let supplyment = TRLotFileSupplyment(animation, bufferSize: bufferSize, queue: Queue())
        supplyment.initialize(fps: 30, startFrame: 0, endFrame: 2)
        return (supplyment, bufferSize)
    }

    private func frame(_ seed: UInt8, size: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: size)
        for i in stride(from: 0, to: size, by: 4) {
            bytes[i] = seed
            bytes[i + 1] = UInt8(truncatingIfNeeded: i / 4)
            bytes[i + 3] = 255
        }
        return Data(bytes)
    }

    func testFinishedAnimationsReleaseTheirEncoderBuffers() {
        let count = 40
        var supplyments: [(TRLotFileSupplyment, Int)] = []
        for i in 0 ..< count {
            let (supplyment, bufferSize) = makeSupplyment("\(i)", side: 64)
            supplyment.addFrame(nil, (frame(UInt8(i), size: bufferSize), 0))
            supplyments.append((supplyment, bufferSize))
        }
        for (supplyment, _) in supplyments {
            _ = supplyment.fps
        }

        let before = mallocInUse()
        for (supplyment, _) in supplyments {
            supplyment.markFinished()
        }
        for (supplyment, _) in supplyments {
            _ = supplyment.fps
        }
        let after = mallocInUse()

        let perAnimation = compression_encode_scratch_buffer_size(COMPRESSION_LZFSE) + supplyments[0].1
        let released = before - after
        print("lottie frame cache: released \(released / 1024) KB for \(count) finished animations, expected about \(count * perAnimation / 1024) KB")
        XCTAssertGreaterThan(released, count * perAnimation * 9 / 10)
    }

    func testFramesStillReadBackAfterTheBuffersAreReleased() {
        let (supplyment, bufferSize) = makeSupplyment("roundtrip", side: 48)
        let first = frame(7, size: bufferSize)
        supplyment.addFrame(nil, (first, 0))
        supplyment.markFinished()
        _ = supplyment.fps
        XCTAssertTrue(supplyment.isFinished)
        XCTAssertEqual(supplyment.readFrame(previous: nil, frame: 0), first)

        let second = frame(9, size: bufferSize)
        supplyment.addFrame(nil, (second, 1))
        _ = supplyment.fps
        XCTAssertEqual(supplyment.readFrame(previous: nil, frame: 1), second, "encoding after finish reallocates its buffers")
        XCTAssertEqual(supplyment.readFrame(previous: nil, frame: 0), first)
    }

    func testSmallAnimationsCacheWithoutKeepingAnEncoderScratch() {
        let count = 40
        let before = mallocInUse()
        var supplyments: [(TRLotFileSupplyment, Int)] = []
        for i in 0 ..< count {
            let (supplyment, bufferSize) = makeSupplyment("small-\(i)", side: 20)
            XCTAssertLessThanOrEqual(bufferSize, TRLotData.transientScratchBufferSize)
            supplyment.addFrame(nil, (frame(UInt8(i), size: bufferSize), 0))
            supplyments.append((supplyment, bufferSize))
        }
        for (supplyment, _) in supplyments {
            _ = supplyment.fps
        }
        let grown = mallocInUse() - before
        let scratch = compression_encode_scratch_buffer_size(COMPRESSION_LZFSE)
        print("lottie frame cache: \(count) small animations caching hold \(grown / 1024) KB, a kept scratch would add \(count * scratch / 1024) KB")
        XCTAssertLessThan(grown, count * scratch / 4)

        let (supplyment, bufferSize) = supplyments[0]
        supplyment.markFinished()
        _ = supplyment.fps
        XCTAssertEqual(supplyment.readFrame(previous: nil, frame: 0), frame(0, size: bufferSize))
    }
}
