import XCTest
import AppKit
@testable import Production

final class RegressionTests: XCTestCase {
    private func image() -> CGImage {
        return CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    func testRemovingLastImageStopsTimer() {
        let cache = ScopedImageCache(countLimit: 10, byteLimit: .max, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
        cache.setImage(image(), sampleBuffer: nil, forKey: 1)
        XCTAssertTrue(cache.isSweeping)
        cache.removeImage(forKey: 1)
        XCTAssertEqual(cache.count, 0)
        XCTAssertFalse(cache.isSweeping)
        cache.setImage(image(), sampleBuffer: nil, forKey: 2)
        XCTAssertTrue(cache.isSweeping)
    }

    func testOversizedImageDoesNotStartEmptyTimer() {
        let cache = ScopedImageCache(countLimit: 10, byteLimit: 0, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
        cache.setImage(image(), sampleBuffer: nil, forKey: 1)
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.cost, 0)
        XCTAssertFalse(cache.isSweeping)
    }

    func testDateFormattersAreIndependent() {
        let first = makeNewDateFormatter()
        first.dateFormat = "yyyy"
        let second = makeNewDateFormatter()
        second.dateFormat = "MM"
        XCTAssertFalse(first === second)
        XCTAssertEqual(first.dateFormat, "yyyy")
    }

    func testMidnightDSTDoesNotIncludeNextDay() {
        let original = NSTimeZone.default
        defer {
            NSTimeZone.default = original
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        }
        NSTimeZone.default = TimeZone(identifier: "America/Sao_Paulo")!
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        let calendar = Calendar.current
        let first = calendar.date(from: DateComponents(year: 2018, month: 11, day: 4, hour: 12))!
        let next = calendar.date(from: DateComponents(year: 2018, month: 11, day: 5, minute: 30))!
        XCTAssertEqual(chatDateId(for: Int32(first.timeIntervalSince1970)), Int64(calendar.startOfDay(for: first).timeIntervalSince1970))
        XCTAssertEqual(chatDateId(for: Int32(next.timeIntervalSince1970)), Int64(calendar.startOfDay(for: next).timeIntervalSince1970))
    }

    func testTimezoneChangeInvalidatesGrouping() {
        let original = NSTimeZone.default
        defer {
            NSTimeZone.default = original
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        }
        let timestamp: Int32 = 1_735_689_600
        _ = chatDateId(for: timestamp)
        _ = mediaDateId(for: timestamp)
        NSTimeZone.default = TimeZone(secondsFromGMT: 14 * 3600)!
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        let calendar = Calendar.current
        XCTAssertEqual(calendar.timeZone.secondsFromGMT(), 14 * 3600)
        let date = Date(timeIntervalSince1970: Double(timestamp))
        XCTAssertEqual(chatDateId(for: timestamp), Int64(calendar.startOfDay(for: date).timeIntervalSince1970))
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let expected = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: month)!
        XCTAssertEqual(mediaDateId(for: timestamp), Int64(expected.timeIntervalSince1970))
    }
}
