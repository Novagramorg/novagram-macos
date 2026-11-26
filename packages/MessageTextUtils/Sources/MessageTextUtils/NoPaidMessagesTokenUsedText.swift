import Foundation
import Localization

public func noPaidMessagesTokenUsedText(peerName: String, isAuthor: Bool) -> (text: String, peerRange: NSRange) {
    let placeholder = "\u{fffc}"
    let template = isAuthor ? strings().notificationNoPaidMessagesTokenUsedYou(placeholder) : strings().notificationNoPaidMessagesTokenUsed(placeholder)
    let range = (template as NSString).range(of: placeholder)
    guard range.location != NSNotFound else {
        return (template, NSRange(location: NSNotFound, length: 0))
    }
    return ((template as NSString).replacingCharacters(in: range, with: peerName), NSRange(location: range.location, length: peerName.utf16.count))
}
