import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocalAnimations
import SettingsUI

private final class AutoremoveCallbackObject : ShareObject {
    private let callback:([PeerId])->Signal<Never, NoError>
    private let currentValue: Int32
    init(_ context: AccountContext, currentValue: Int32, callback:@escaping([PeerId])->Signal<Never, NoError>) {
        self.currentValue = currentValue
        self.callback = callback
        super.init(context)
    }
    
    override var hasCaptionView: Bool {
        return false
    }
    override var blockCaptionView: Bool {
        return true
    }
    
    override var hasFolders: Bool {
        return false
    }
    
    override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars: [PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return callback(peerIds) |> castError(String.self)
    }
 
    override var searchPlaceholderKey: String {
        return "ChatList.Add.Placeholder"
    }
    override var interactionOk: String {
        return strings().globalTimerSelectApply(timeIntervalString(Int(currentValue)))
    }
    override var alwaysEnableDone: Bool {
        return true
    }
    override func possibilityPerformTo(_ peer: Peer) -> Bool {
        if peer.isSecretChat || peer.isBot {
            return false
        }
        if peer.isUser {
            return true
        }
        if peer.groupAccess.canEditGroupInfo {
            return true
        }
        return false
    }
    
    override func statusString(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> String? {
        if let value = autoDeletion {
            return strings().globalTimerSelectStatusEnabled(timeIntervalString(Int(value)))
        } else {
            return strings().globalTimerSelectStatusDisabled
        }
    }
    
    override func statusStyle(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> ControlStyle {
        let color: NSColor
        if autoDeletion != nil {
            color = theme.colors.accent
        } else {
            color = theme.colors.grayText
        }
        return ControlStyle(font: .normal(.text), foregroundColor: color, highlightColor: theme.colors.underSelectedColor)

    }
    
}

func installGlobalAutoremoveUIHooks() {
    GlobalAutoremoveHooks.install(GlobalAutoremoveHooks(
        makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, stickerSize, bgColor, image in
        AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, stickerSize: stickerSize, bgColor: bgColor, image: image) },
        showApplyToExisting: { context, currentValue, callback in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(AutoremoveCallbackObject(context, currentValue: currentValue, callback: callback)), for: context.window) }
    ))
}
