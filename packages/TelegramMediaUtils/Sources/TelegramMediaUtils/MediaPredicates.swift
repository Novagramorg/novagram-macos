import Foundation
import TelegramCore
import Postbox

public extension Media {
    var isInteractiveMedia: Bool {
        if self is TelegramMediaImage {
            return true
        } else if let file = self as? TelegramMediaFile {
            return (file.isVideo && !file.isWebm) || (file.isAnimated && !file.mimeType.lowercased().hasSuffix("gif") && !file.isWebm)
        } else if let map = self as? TelegramMediaMap {
            return map.venue == nil
        } else if self is TelegramMediaDice {
            return false
        } else if self is TelegramMediaPaidContent {
            return true
        }
        return false
    }
    var isInstantVideo: Bool {
        if let media = self as? TelegramMediaFile {
            return media.isInstantVideo
        }
        return false
    }
    var isMusicFile: Bool {
        if let media = self as? TelegramMediaFile {
            for attr in media.attributes {
                switch attr {
                case let .Audio(isVoice, _, _, _, _):
                    return !isVoice
                default:
                    return false
                }
            }
        }
        return false
    }
}
