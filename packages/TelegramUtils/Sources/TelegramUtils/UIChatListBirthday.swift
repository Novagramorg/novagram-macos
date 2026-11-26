import Foundation
import TelegramCore

public struct UIChatListBirthday : Equatable {
    public let birthday: TelegramBirthday
    public let peer: EnginePeer
    public init(birthday: TelegramBirthday, peer: EnginePeer) {
        self.birthday = birthday
        self.peer = peer
    }
}
