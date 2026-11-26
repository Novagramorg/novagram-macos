import XCTest
@testable import Production

final class DateGroupingTests: XCTestCase {
    private func referenceMonth(_ timestamp: Int32, _ calendar: Calendar) -> Int64 {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        return Int64(calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!.timeIntervalSince1970)
    }

    func testCalendarAndTimezoneMatrix() {
        let calendars: [Calendar.Identifier] = [.gregorian, .iso8601, .buddhist, .hebrew, .islamic, .japanese, .chinese, .persian, .indian]
        let zones = ["UTC", "America/Los_Angeles", "America/Sao_Paulo", "America/Asuncion", "Australia/Lord_Howe", "Pacific/Apia", "Asia/Kathmandu", "Europe/Berlin"]
        var seed: UInt64 = 42
        for identifier in calendars {
            for zone in zones {
                var calendar = Calendar(identifier: identifier)
                calendar.timeZone = TimeZone(identifier: zone)!
                let cache = ChatDateGroupingCache(calendarProvider: { calendar }, notificationCenter: NotificationCenter())
                var timestamps: [Int32] = [.min, .max, 0, -1, 1, 1_735_689_600]
                for _ in 0 ..< 400 {
                    seed = seed &* 6364136223846793005 &+ 1
                    timestamps.append(Int32(truncatingIfNeeded: seed >> 32))
                }
                for timestamp in timestamps {
                    let date = Date(timeIntervalSince1970: Double(timestamp))
                    let expectedDay = Int64(calendar.startOfDay(for: date).timeIntervalSince1970)
                    let expectedMonth = referenceMonth(timestamp, calendar)
                    for _ in 0 ..< 2 {
                        XCTAssertEqual(cache.dayId(for: timestamp), expectedDay, "\(identifier) \(zone) \(timestamp)")
                        XCTAssertEqual(cache.monthId(for: timestamp), expectedMonth, "\(identifier) \(zone) \(timestamp)")
                    }
                    let month = calendar.dateInterval(of: .month, for: date)!
                    for edge in [month.start, month.end.addingTimeInterval(-1), month.end] {
                        if let value = Int32(exactly: Int64(edge.timeIntervalSince1970)) {
                            XCTAssertEqual(cache.monthId(for: value), referenceMonth(value, calendar), "\(identifier) \(zone) month edge \(value)")
                        }
                    }
                }
            }
        }
    }

    func testDSTAndSkippedDayBoundaries() {
        for (zone, year, month, day) in [("America/Sao_Paulo", 2018, 11, 4), ("America/Asuncion", 2017, 10, 1), ("Australia/Lord_Howe", 2024, 10, 6), ("America/Los_Angeles", 2024, 11, 3), ("Pacific/Apia", 2011, 12, 29)] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let cache = ChatDateGroupingCache(calendarProvider: { calendar }, notificationCenter: NotificationCenter())
            let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            for step in 0 ..< 144 {
                let date = start.addingTimeInterval(Double(step * 1800))
                let timestamp = Int32(date.timeIntervalSince1970)
                XCTAssertEqual(cache.dayId(for: timestamp), Int64(calendar.startOfDay(for: date).timeIntervalSince1970), "\(zone) \(date)")
                XCTAssertEqual(cache.monthId(for: timestamp), referenceMonth(timestamp, calendar))
            }
        }
    }

    func testLocaleAndTimezoneNotificationsRefreshBothCaches() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let center = NotificationCenter()
        let cache = ChatDateGroupingCache(calendarProvider: { calendar }, notificationCenter: center)
        let timestamp: Int32 = 1_735_689_600
        for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
            _ = cache.dayId(for: timestamp)
            _ = cache.monthId(for: timestamp)
            calendar.timeZone = TimeZone(secondsFromGMT: calendar.timeZone.secondsFromGMT() == 0 ? 14 * 3600 : 0)!
            center.post(name: name, object: nil)
            XCTAssertEqual(cache.dayId(for: timestamp), Int64(calendar.startOfDay(for: Date(timeIntervalSince1970: Double(timestamp))).timeIntervalSince1970))
            XCTAssertEqual(cache.monthId(for: timestamp), referenceMonth(timestamp, calendar))
        }
    }

    func testConcurrentMissesHitsAndInvalidations() {
        var fixed = Calendar(identifier: .gregorian)
        fixed.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let calendar = fixed
        let center = NotificationCenter()
        let cache = ChatDateGroupingCache(calendarProvider: { calendar }, notificationCenter: center)
        let timestamps = (0 ..< 64).map { Int32(1_700_000_000 + $0 * 86400 * 17) }
        let days = timestamps.map { Int64(calendar.startOfDay(for: Date(timeIntervalSince1970: Double($0))).timeIntervalSince1970) }
        let months = timestamps.map { referenceMonth($0, calendar) }
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for step in 0 ..< 1000 {
                let index = (worker * 13 + step) % timestamps.count
                XCTAssertEqual(cache.dayId(for: timestamps[index]), days[index])
                XCTAssertEqual(cache.monthId(for: timestamps[index]), months[index])
                if step % 47 == 0 {
                    center.post(name: .NSSystemTimeZoneDidChange, object: nil)
                }
            }
        }
    }

    func testObserversDoNotRetainCache() {
        let center = NotificationCenter()
        weak var released: ChatDateGroupingCache?
        autoreleasepool {
            let cache = ChatDateGroupingCache(notificationCenter: center)
            released = cache
        }
        XCTAssertNil(released)
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
    }
}
