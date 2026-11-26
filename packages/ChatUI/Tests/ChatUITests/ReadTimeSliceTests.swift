import XCTest
@testable import ChatUI

final class ReadTimeSliceTests: XCTestCase {
    private func sampled(duration: Double, activity: [Double], timeout: Double) -> (Int, Int) {
        var total = 0, active = 0
        var t = 0.2
        while t <= duration + 1e-9 {
            total += 200
            if let last = activity.filter({ $0 <= t }).max(), t - last < timeout {
                active += 200
            }
            t += 0.2
        }
        return (total, active)
    }

    private func eventDriven(duration: Double, activity: [Double], timeout: Double) -> (Int, Int) {
        var total = 0, active = 0
        var last = activity.filter { $0 <= 0 }.max() ?? -1000
        var from = 0.0
        for event in activity.filter({ $0 > 0 && $0 <= duration }).sorted() {
            let slice = ReadTimeSlice.between(from, event, activeUntil: last + timeout)
            total += slice.totalMs
            active += slice.activeMs
            from = event
            last = event
        }
        let slice = ReadTimeSlice.between(from, duration, activeUntil: last + timeout)
        return (total + slice.totalMs, active + slice.activeMs)
    }

    func testEventDrivenTimeMatchesTheOldFiveHertzSampling() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 200 {
            let duration = Double.random(in: 1 ..< 300, using: &generator)
            let activity = [0.0] + (0 ..< Int.random(in: 0 ..< 12, using: &generator)).map { _ in Double.random(in: 0 ..< duration, using: &generator) }
            let old = sampled(duration: duration, activity: activity, timeout: 15)
            let new = eventDriven(duration: duration, activity: activity, timeout: 15)
            XCTAssertEqual(Double(new.0), Double(old.0), accuracy: 201 + Double(activity.count))
            XCTAssertEqual(Double(new.1), Double(old.1), accuracy: 200 * Double(activity.count + 1) + Double(activity.count))
            XCTAssertLessThanOrEqual(new.1, new.0)
        }
    }

    func testSliceSplitsAtTheEndOfActivity() {
        let slice = ReadTimeSlice.between(10, 40, activeUntil: 25)
        XCTAssertEqual(slice, ReadTimeSlice(totalMs: 30000, activeMs: 15000))
        XCTAssertEqual(ReadTimeSlice.between(10, 20, activeUntil: 5), ReadTimeSlice(totalMs: 10000, activeMs: 0))
        XCTAssertEqual(ReadTimeSlice.between(10, 20, activeUntil: 50), ReadTimeSlice(totalMs: 10000, activeMs: 10000))
    }
}
