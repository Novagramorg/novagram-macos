import Foundation
import TelegramCore

public struct CallTerminationOutcome: Equatable {
    public let error: CallSessionError?
    public let ratingCallId: CallId?
}

public func callTerminationOutcome(_ state: CallSessionState) -> CallTerminationOutcome? {
    guard case let .terminated(id, reason, options) = state else {
        return nil
    }
    var error: CallSessionError?
    if case let .error(value) = reason {
        error = value
    }
    return CallTerminationOutcome(error: error, ratingCallId: options.contains(.reportRating) ? id : nil)
}
