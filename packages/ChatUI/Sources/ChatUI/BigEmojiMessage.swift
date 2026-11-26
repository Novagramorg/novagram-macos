import Foundation
import TelegramCore
import Postbox
import InAppSettings
import MessageUtils

public func bigEmojiMessage(_ settings: BaseApplicationSettings, message: Message) -> Bool {
    guard settings.bigEmoji,
          message.media.isEmpty,
          message.replyMarkup == nil,
          message.adAttribute == nil else {
        return false
    }
    for entity in message.entities {
        switch entity.type {
        case .CustomEmoji:
            continue
        default:
            return false
        }
    }
    let text = message.text
    if text.isEmpty {
        return false
    }
    var nextShouldBeVariationSelector = false
    var hasContent = false
    for scalar in text.unicodeScalars {
        if scalar == " " || scalar == "\n" {
            continue
        }
        hasContent = true
        if nextShouldBeVariationSelector {
            if scalar == UnicodeScalar.VariationSelector {
                nextShouldBeVariationSelector = false
                continue
            } else {
                return false
            }
        }
        if !scalar.isEmoji && scalar.maybeEmoji {
            nextShouldBeVariationSelector = true
        } else if !scalar.isEmoji && scalar != UnicodeScalar.ZeroWidthJoiner {
            return false
        }
    }
    return hasContent && !nextShouldBeVariationSelector
}
