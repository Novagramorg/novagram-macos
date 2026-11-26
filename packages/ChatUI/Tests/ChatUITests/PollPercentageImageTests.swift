import XCTest
import AppKit
import ColorPalette
@testable import TelegramTheme

final class PollPercentageImageTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func bytes(_ image: CGImage) -> Int {
        return image.bytesPerRow * image.height
    }

    func testStaticPollBuildsOnlyTheShownValue() {
        let colors = TelegramChatColors(dayClassicPalette, true)
        let first = colors.pollPercentAnimatedIcon(true, true, value: 42)
        let again = colors.pollPercentAnimatedIcon(true, true, value: 42)
        XCTAssertTrue(first === again)
        XCTAssertEqual(colors.generatedPercentageImageCount, 1)

        _ = colors.pollPercentAnimatedIcon(false, true, value: 42)
        _ = colors.pollPercentAnimatedIcon(true, false, value: 7)
        XCTAssertEqual(colors.generatedPercentageImageCount, 3)
        XCTAssertLessThan(bytes(first) * 3, 101 * bytes(first), "a static poll used to build all 101 images per variant")
    }

    func testAnimationFramesAreTheRoundedValues() {
        let colors = TelegramChatColors(dayClassicPalette, true)
        let duration = 0.25
        let frames = colors.pollPercentAnimatedIcons(false, true, from: 10, to: 40, duration: duration)
        let count = max(1, Int(duration / (1.0 / 60)))
        XCTAssertEqual(frames.count, count)
        for (i, frame) in frames.enumerated() {
            let t = CGFloat(i) / CGFloat(count)
            let value = Int(round((1.0 - t) * 10 + t * 40))
            XCTAssertTrue(frame === colors.percentageImage(.outgoingBubbled, value: value), "frame \(i)")
        }
        XCTAssertLessThanOrEqual(colors.generatedPercentageImageCount, 31)
    }

    func testValuesAreClampedToTheRange() {
        let colors = TelegramChatColors(dayClassicPalette, false)
        XCTAssertTrue(colors.pollPercentAnimatedIcon(false, false, value: -3) === colors.pollPercentAnimatedIcon(false, false, value: 0))
        XCTAssertTrue(colors.pollPercentAnimatedIcon(false, false, value: 140) === colors.pollPercentAnimatedIcon(false, false, value: 100))
        XCTAssertEqual(colors.generatedPercentageImageCount, 2)
    }

    private func dominantColor(_ image: CGImage) -> (CGFloat, CGFloat, CGFloat)? {
        let width = image.width, height = image.height
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var best: (CGFloat, CGFloat, CGFloat)?
        var bestAlpha: UInt8 = 0
        for i in 0 ..< width * height where pixels[i * 4 + 3] > bestAlpha {
            bestAlpha = pixels[i * 4 + 3]
            let a = CGFloat(bestAlpha)
            best = (CGFloat(pixels[i * 4]) / a, CGFloat(pixels[i * 4 + 1]) / a, CGFloat(pixels[i * 4 + 2]) / a)
        }
        return bestAlpha > 200 ? best : nil
    }

    func testEachVariantUsesItsOwnTextColor() throws {
        let path = NSTemporaryDirectory() + "poll-percentage-test.palette"
        try "name = PollTest\nisDark = 0\ntext = #ff0000\ntextBubble_incoming = #00ff00\ntextBubble_outgoing = #0000ff\n".write(toFile: path, atomically: true, encoding: .utf8)
        let palette = try XCTUnwrap(importPalette(path))
        let colors = TelegramChatColors(palette, true)
        let plain = try XCTUnwrap(dominantColor(colors.pollPercentAnimatedIcon(true, false, value: 88)))
        let incoming = try XCTUnwrap(dominantColor(colors.pollPercentAnimatedIcon(true, true, value: 88)))
        let outgoing = try XCTUnwrap(dominantColor(colors.pollPercentAnimatedIcon(false, true, value: 88)))
        XCTAssertGreaterThan(plain.0, 0.8)
        XCTAssertGreaterThan(incoming.1, 0.8)
        XCTAssertGreaterThan(outgoing.2, 0.8)
    }

    func testConcurrentReadersGetOneImagePerValue() {
        let colors = TelegramChatColors(dayClassicPalette, true)
        let results = (0 ..< 8).map { _ in NSMutableArray() }
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for value in 0 ... 100 {
                results[worker].add(colors.pollPercentAnimatedIcon(true, true, value: value))
            }
        }
        for value in 0 ... 100 {
            let first = results[0][value] as AnyObject
            for worker in 1 ..< 8 {
                XCTAssertTrue(first === (results[worker][value] as AnyObject), "value \(value) worker \(worker)")
            }
        }
        XCTAssertEqual(colors.generatedPercentageImageCount, 101)
    }

    func testFirstStaticIconIsCheaperThanBuildingTheWholeSet() {
        let lazy = TelegramChatColors(dayClassicPalette, true)
        var started = CFAbsoluteTimeGetCurrent()
        _ = lazy.pollPercentAnimatedIcon(true, true, value: 50)
        let firstIcon = CFAbsoluteTimeGetCurrent() - started

        let eager = TelegramChatColors(dayClassicPalette, true)
        started = CFAbsoluteTimeGetCurrent()
        for value in 0 ... 100 {
            _ = eager.pollPercentAnimatedIcon(true, true, value: value)
        }
        let wholeSet = CFAbsoluteTimeGetCurrent() - started
        print("poll percentage: first icon \(Int(firstIcon * 1_000_000)) µs, old eager set \(Int(wholeSet * 1_000_000)) µs")
        XCTAssertLessThan(firstIcon, wholeSet)
    }
}
