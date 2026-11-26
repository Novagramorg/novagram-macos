import Foundation
import Postbox
import TelegramCore

public enum RelativeUserPresenceStatus {
    case offline
    case online(at: Int32)
    case lastSeen(at: Int32)
    case recently
    case lastWeek
    case lastMonth
}

public func relativeUserPresenceStatus(_ presence: TelegramUserPresence, timeDifference: TimeInterval, relativeTo timestamp: Int32) -> RelativeUserPresenceStatus {
    switch presence.status {
    case .none:
        return .offline
    case let .present(statusTimestamp):
        let statusTimestampInt: Int = Int(statusTimestamp)
        let statusTimestamp = Int32(min(statusTimestampInt - Int(timeDifference), Int(INT32_MAX)))
        if statusTimestamp >= timestamp {
            return .online(at: statusTimestamp)
        } else {
            return .lastSeen(at: statusTimestamp)
        }

    case .recently:
        let activeUntil = presence.lastActivity - Int32(timeDifference) + 30
        if activeUntil >= timestamp {
            return .online(at: activeUntil)
        } else {
            return .recently
        }
    case .lastWeek:
        return .lastWeek
    case .lastMonth:
        return .lastMonth
    }
}
