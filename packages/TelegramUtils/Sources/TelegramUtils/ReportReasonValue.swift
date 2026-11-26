import Foundation
import TelegramCore

public struct ReportReasonValue : Equatable {
    public let reason: ReportReason
    public let comment: String

    public init(reason: ReportReason, comment: String) {
        self.reason = reason
        self.comment = comment
    }
}
