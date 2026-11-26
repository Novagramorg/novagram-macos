import Foundation
import Postbox
import TelegramCore

extension TelegramPeerPhoto : @retroactive Equatable {
    public static func ==(lhs: TelegramPeerPhoto, rhs: TelegramPeerPhoto) -> Bool {
        if lhs.date != rhs.date {
            return false
        }
        if !lhs.image.isEqual(to: rhs.image) {
            return false
        }
        if lhs.index != rhs.index {
            return false
        }
        if lhs.messageId != rhs.messageId {
            return false
        }
        if lhs.reference != rhs.reference {
            return false
        }
        if lhs.totalCount != rhs.totalCount {
            return false
        }
        return true
    }
}
