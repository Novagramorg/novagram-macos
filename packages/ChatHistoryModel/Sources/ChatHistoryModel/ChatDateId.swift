import Foundation

final class ChatDateGroupingCache {
    private struct Boundary {
        let start: Int64
        let end: Int64
        let id: Int64

        func contains(_ timestamp: Int64) -> Bool {
            return timestamp >= start && timestamp < end
        }
    }

    private let lock = NSLock()
    private let calendarProvider: () -> Calendar
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var calendar: Calendar
    private var days: [Boundary] = []
    private var months: [Boundary] = []
    private let capacity = 16

    init(calendarProvider: @escaping () -> Calendar = { Calendar.current }, notificationCenter: NotificationCenter = .default) {
        self.calendarProvider = calendarProvider
        self.calendar = calendarProvider()
        self.notificationCenter = notificationCenter
        for name in [Notification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.invalidate()
            })
        }
        invalidate()
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    private func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        calendar = calendarProvider()
        days.removeAll(keepingCapacity: true)
        months.removeAll(keepingCapacity: true)
    }

    func dayId(for timestamp: Int32) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = Int64(timestamp)
        if let boundary = days.reversed().first(where: { $0.contains(timestamp) }) {
            return boundary.id
        }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let interval = calendar.dateInterval(of: .day, for: date)!
        let start = Int64(interval.start.timeIntervalSince1970)
        if days.count >= capacity {
            days.removeFirst()
        }
        days.append(Boundary(start: start, end: Int64(interval.end.timeIntervalSince1970), id: start))
        return start
    }

    func monthId(for timestamp: Int32) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = Int64(timestamp)
        if let boundary = months.reversed().first(where: { $0.contains(timestamp) }) {
            return boundary.id
        }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let interval: DateInterval?
        let startMonth: Date
        if calendar.identifier == .gregorian || calendar.identifier == .iso8601 {
            let monthInterval = calendar.dateInterval(of: .month, for: date)!
            interval = monthInterval
            startMonth = monthInterval.start
        } else {
            interval = nil
            startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        }
        let lastDay = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startMonth)!
        let id = Int64(lastDay.timeIntervalSince1970)
        guard let interval = interval else {
            return id
        }
        if months.count >= capacity {
            months.removeFirst()
        }
        months.append(Boundary(start: Int64(interval.start.timeIntervalSince1970), end: Int64(interval.end.timeIntervalSince1970), id: id))
        return id
    }
}

private let chatDateGroupingCache = ChatDateGroupingCache()

public func chatDateId(for timestamp: Int32) -> Int64 {
    return chatDateGroupingCache.dayId(for: timestamp)
}

public func mediaDateId(for timestamp: Int32) -> Int64 {
    return chatDateGroupingCache.monthId(for: timestamp)
}
