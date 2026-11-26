import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import ColorPalette
import ThemeSettings
import GalleryUI

public func sharedMediaGalleryType(for message: Message, fallback: GalleryAppearType, preparedMessages: @autoclosure () -> [Message]) -> GalleryAppearType {
    if message.richText != nil {
        return .messages(preparedMessages())
    }
    return fallback
}
