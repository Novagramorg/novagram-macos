func timestamp(_ value: String) -> Int32 {
    return Int32(ISO8601DateFormatter().date(from: value)!.timeIntervalSince1970)
}

let cases: [(String, String, String, String)] = [
    ("UTC", "2026-04-21T12:00:00Z", "2026-04-21T00:00:00Z", "2026-04-22T00:00:00Z"),
    ("America/New_York", "2026-03-08T12:00:00Z", "2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z"),
    ("America/New_York", "2026-11-01T12:00:00Z", "2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z"),
    ("Asia/Kathmandu", "2026-04-21T12:00:00Z", "2026-04-20T18:15:00Z", "2026-04-21T18:15:00Z"),
    ("UTC", "2024-02-29T12:00:00Z", "2024-02-29T00:00:00Z", "2024-03-01T00:00:00Z"),
    ("UTC", "2026-12-31T12:00:00Z", "2026-12-31T00:00:00Z", "2027-01-01T00:00:00Z")
]

var checks = 0
for (zone, date, start, end) in cases {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    for offset: TimeInterval in [0, 120, -120, 0.5, -0.5] {
        let range = chatDateMessageRange(timestamp: timestamp(date), timeDifference: offset, calendar: calendar)!
        let lower = Int32(ceil(Double(timestamp(start)) + offset))
        let upper = Int32(ceil(Double(timestamp(end)) + offset)) - 1
        precondition(range.min == lower && range.max == upper, "Incorrect day range for \(zone), \(date), \(offset)")
        for candidate in [range.min - 1, range.min, range.max, range.max + 1] {
            let displayTimestamp = Int32(Double(candidate) - offset)
            let sameDay = calendar.isDate(Date(timeIntervalSince1970: Double(displayTimestamp)), inSameDayAs: Date(timeIntervalSince1970: Double(timestamp(date))))
            precondition(sameDay == (candidate >= range.min && candidate <= range.max), "Count boundaries disagree with displayed day")
        }
        checks += 1
    }
}
precondition(chatDateMessageRange(timestamp: Int32.max, timeDifference: 0) == nil)
precondition(chatDateMessageRange(timestamp: 0, timeDifference: 0) == nil)
print("Passed \(checks + 2) date-range cases, including DST, fractional clock offsets and unsupported bounds")
