import Foundation
import TelegramCore
import Postbox
import TelegramTheme
import TelegramUtils

extension Message {
    public func newReactions(with reaction: UpdateMessageReaction, isTags: Bool) -> [UpdateMessageReaction] {
        var updated:[UpdateMessageReaction] = []
        if let reactions = self.effectiveReactions(isTags: isTags) {
            
            let sorted = reactions.sorted(by: <)
            
            updated = sorted.compactMap { value in
                if value.isSelected {
                    switch value.value {
                    case let .builtin(emoji):
                        return .builtin(emoji)
                    case let .custom(fileId):
                        let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                        let file = self.associatedMedia[mediaId] as? TelegramMediaFile
                        return .custom(fileId: fileId, file: file)
                    case .stars:
                        return .stars
                    }
                }
                return nil
            }
            if let index = updated.firstIndex(where: { $0.reaction == reaction.reaction }) {
                updated.remove(at: index)
            } else {
                updated.append(reaction)
            }
        } else {
            updated.append(reaction)
        }
        return updated.filter { value in
            switch value {
            case .stars:
                return false
            default:
                return true
            }
        }
    }

    public func possibilityForwardTo(_ peer:Peer) -> Bool {
        if !peer.canSendMessage(false) {
            return false
        } else if let peer = peer as? TelegramChannel {
            if peer.isChannel, media.first is TelegramMediaTodo {
                return false
            }
            if let media = media.first, !(media is TelegramMediaWebpage) {
                if let media = media as? TelegramMediaFile {
                    if media.isStaticSticker {
                        return !peer.hasBannedRights(.banSendStickers)
                    } else if media.isVideo && media.isAnimated {
                        return !peer.hasBannedRights(.banSendGifs)
                    }
                }
                return !peer.hasBannedRights(.banSendMedia)
            }
        }
        return true
    }
}
