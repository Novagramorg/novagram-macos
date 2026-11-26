import Cocoa
import TelegramCore
import Postbox

public extension Message {
    var anyMedia: Media? {
        if let media = self.media.first as? TelegramMediaInvoice {
            if let extended = media.extendedMedia {
                switch extended {
                case let .full(media):
                    return media
                default:
                    break
                }
            }
        } else if let media = self.media.first as? TelegramMediaAction {
            switch media.action {
            case let .suggestedProfilePhoto(image):
                return image
            case let .photoUpdated(image):
                 return image
            default:
                break
            }
        } else if let media = self.media.first as? TelegramMediaStory, let story = associatedStories[media.storyId]?.get(Stories.StoredItem.self) {
            switch story {
            case let .item(item):
                return item.media
            default:
                return media
            }
        }
        return media.first
    }
}
