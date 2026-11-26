import TelegramCore
import Postbox

public extension TelegramMediaFile {
    var paintToText:Bool {
        for attr in attributes {
            if case let .CustomEmoji(_, paintToText, _, _) = attr {
                return paintToText
            }
        }
        return false
    }

    var emojiReference:StickerPackReference? {
        for attr in attributes {
            if case let .CustomEmoji(_, _, _, reference) = attr {
                return reference
            }
        }
        return nil
    }

}

public extension Media {
    var isWebm: Bool {
        if let media = self as? TelegramMediaFile {
            return media.mimeType == "video/webm"
        }
        return false
    }

}
