import Foundation
import TGUIKit
import ChatModeTypes
import InputDataUI

public final class ChatHistoryEntryIdentifier : InputDataIdentifier {
    private let entryId: ChatHistoryEntryId
    public init(_ entryId: ChatHistoryEntryId) {
        self.entryId = entryId
        super.init("id")
    }
    public override func isEqual(to: InputDataIdentifier) -> Bool {
        if let to = to as? ChatHistoryEntryIdentifier {
            return to.entryId == self.entryId
        } else {
            return false
        }
    }
}
