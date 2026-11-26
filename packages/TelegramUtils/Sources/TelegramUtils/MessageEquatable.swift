import Foundation
import Postbox

extension Message : @retroactive Equatable {
    public static func ==(lhs: Message, rhs: Message) -> Bool {
        return isEqualMessages(lhs, rhs)
    }
}
