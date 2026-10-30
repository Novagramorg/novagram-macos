import Cocoa
import Postbox
import TelegramCore
import NovagramCore

// MARK: - Privacy

// A hidden chat (Novagram Hidden Chats) never shows in search, even while hidden chats are revealed.
func novagramSearchHides(_ peerId: PeerId) -> Bool {
    return NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId)
}

func novagramSearchHides(_ rendered: RenderedPeer) -> Bool {
    if novagramSearchHides(rendered.peerId) {
        return true
    }
    if let main = rendered.chatMainPeer, novagramSearchHides(main.id) {
        return true
    }
    return false
}

// Message results also skip chats locked with Chat Lock: the lock guards the content, while the chat
// name may still show (as in the chat list).
func novagramSearchPrivateMessages(_ messages: [Message]) -> [Message] {
    return NovagramSearchPrivacy.kept(messages, message: { $0 })
}
