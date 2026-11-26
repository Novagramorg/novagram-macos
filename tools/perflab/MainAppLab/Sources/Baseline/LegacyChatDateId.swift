import Foundation

private let _chatGroupingCalendar = Calendar.current

private struct ChatDayBoundary {
    let startUnix: Int64
    let endUnix: Int64
    let dayId: Int64
}
private var _chatDateCache: [ChatDayBoundary] = []
private let _chatDateCacheLock = NSLock()
private let _chatDateCacheCapacity = 16

public func legacyChatDateId(for timestamp: Int32) -> Int64 {
    let ts = Int64(timestamp)
    _chatDateCacheLock.lock()
    for boundary in _chatDateCache {
        if ts >= boundary.startUnix && ts < boundary.endUnix {
            _chatDateCacheLock.unlock()
            return boundary.dayId
        }
    }
    _chatDateCacheLock.unlock()

    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let startOfDay = _chatGroupingCalendar.startOfDay(for: date)
    let endOfDay = _chatGroupingCalendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
    let startUnix = Int64(startOfDay.timeIntervalSince1970)
    let endUnix = Int64(endOfDay.timeIntervalSince1970)
    let dayId = startUnix

    _chatDateCacheLock.lock()
    if _chatDateCache.count >= _chatDateCacheCapacity {
        _chatDateCache.removeFirst()
    }
    _chatDateCache.append(ChatDayBoundary(startUnix: startUnix, endUnix: endUnix, dayId: dayId))
    _chatDateCacheLock.unlock()
    return dayId
}

public func legacyMediaDateId(for timestamp: Int32) -> Int64 {
    let startMonth = _chatGroupingCalendar.date(from: _chatGroupingCalendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: TimeInterval(timestamp))))!
    let endMonth = _chatGroupingCalendar.date(byAdding: DateComponents(month: 1, day: -1), to: startMonth)!
    return Int64(endMonth.timeIntervalSince1970)
}
