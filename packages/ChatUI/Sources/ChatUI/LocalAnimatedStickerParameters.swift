import Cocoa
import TelegramCore
import TelegramMedia
import Postbox
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import LocalAnimations

extension LocalAnimatedSticker {
    public var parameters: ChatAnimatedStickerMediaLayoutParameters {
        let playPolicy: LottiePlayPolicy?
        var hidePlayer: Bool = true
        var thumbAtFrame: Int = 0
        switch self {
        case .brilliant_static:
            playPolicy = .loop
        case .brilliant_loading:
            playPolicy = .loop
        case .smart_guy:
            playPolicy = .once
        case .fly_dollar:
            playPolicy = .loop
        case .gift:
            playPolicy = .once
        case .keychain:
            playPolicy = .once
        case .keyboard_typing:
            playPolicy = .once
        case .swap_money:
            playPolicy = .once
        case .write_words:
            playPolicy = .once
        case .chiken_born:
            playPolicy = .loop
        case .sad:
            playPolicy = .once
        case .success:
            playPolicy = .once
        case .monkey_unsee:
            playPolicy = .once
        case .monkey_see:
            playPolicy = .once
        case .think_spectacular:
            playPolicy = .once
        case .success_saved:
            playPolicy = .onceEnd
            hidePlayer = false
            thumbAtFrame = 60
        case .dice_idle:
            playPolicy = .once
        case .folder:
            playPolicy = .once
        case .new_folder:
            playPolicy = .loop
        case .folder_empty:
            playPolicy = .loop
        case .graph_loading:
            playPolicy = .loop
            hidePlayer = false
        case .dart_idle:
            playPolicy = .once
        case .discussion:
            playPolicy = .loop
            hidePlayer = false
        case .group_call_chatlist_typing:
            playPolicy = .loop
            hidePlayer = false
        case .invitations:
            playPolicy = .loop
            hidePlayer = false
        case .destructor:
            playPolicy = .loop
            hidePlayer = false
        case .gigagroup:
            playPolicy = .loop
            hidePlayer = false
        case .police:
            playPolicy = .loop
            hidePlayer = false
        case .premium_gift_3:
            playPolicy = .onceEnd
        case .premium_gift_6:
            playPolicy = .onceEnd
        case .premium_gift_12:
            playPolicy = .onceEnd
        case .show_status_read:
            playPolicy = .onceEnd
        case .show_status_profile:
            playPolicy = .onceEnd
        case .business_hours:
            playPolicy = .onceEnd
        case .business_location:
            playPolicy = .onceEnd
        case .business_quick_reply:
            playPolicy = .onceEnd
        case .business_chatbot:
            playPolicy = .onceEnd
        case .business_away_message:
            playPolicy = .onceEnd
        case .business_links:
            playPolicy = .onceEnd
        case .business_greeting_message:
            playPolicy = .onceEnd
        case .fragment_username:
            playPolicy = .onceEnd
        case .fragment:
            playPolicy = .onceEnd
        case .ton_logo:
            playPolicy = .onceEnd
        case .affiliate_link:
            playPolicy = .onceEnd
        case .freeze_duck:
            playPolicy = .onceEnd
        case .topics:
            playPolicy = .onceEnd
        default:
            playPolicy = .loop
            hidePlayer = false
        }
        return ChatAnimatedStickerMediaLayoutParameters(playPolicy: playPolicy, alwaysAccept: true, cache: .temporaryLZ4(.thumb), hidePlayer: hidePlayer, media: self.file, shimmer: false, thumbAtFrame: thumbAtFrame)
    }
}
