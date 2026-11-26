import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore


extension ChatListFilter {
    var id: Int32 {
        switch self {
        case .allChats:
            return -1
        case let .filter(id, _, _, _):
            return id
        }
    }
}
