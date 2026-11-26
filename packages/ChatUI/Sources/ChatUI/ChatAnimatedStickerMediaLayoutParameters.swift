import Cocoa
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import TelegramMedia
import TGUIKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils

public final class ChatAnimatedStickerMediaLayoutParameters : ChatMediaLayoutParameters {
    public let playPolicy: LottiePlayPolicy?
    public let alwaysAccept: Bool?
    public let cache: ASCachePurpose?
    public let hidePlayer: Bool?
    public let playOnHover: Bool?
    public let thumbAtFrame: Int
    public let shimmer: Bool
    public let noThumb: Bool
    public init(playPolicy: LottiePlayPolicy?, alwaysAccept: Bool? = nil, cache: ASCachePurpose? = nil, hidePlayer: Bool = false, media: TelegramMediaFile, colors: [LottieColor] = [], playOnHover: Bool? = nil, shimmer: Bool = true, thumbAtFrame: Int = 0, noThumb: Bool = false) {
        self.playPolicy = playPolicy
        self.alwaysAccept = alwaysAccept
        self.cache = cache
        self.hidePlayer = hidePlayer
        self.playOnHover = playOnHover
        self.shimmer = shimmer
        self.thumbAtFrame = thumbAtFrame
        self.noThumb = noThumb
        super.init(presentation: .empty, media: media, automaticDownload: true, autoplayMedia: AutoplayMediaPreferences.defaultSettings, colors: colors)
    }
}
