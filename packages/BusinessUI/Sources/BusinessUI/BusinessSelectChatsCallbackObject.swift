import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import AlertsUI
import InputView
import ChatModeTypes

public class BusinessSelectChatsCallbackObject : ShareObject {
    private let callback:([PeerId])->Signal<Never, NoError>
    private let limitReachedText: String
    private let contacts: Set<PeerId>
    public init(_ context: any AccountContextProtocol, defaultSelectedIds: Set<PeerId>, contacts: Set<PeerId> = Set(), additionTopItems: ShareAdditionItems?, limit: Int?, limitReachedText: String, callback:@escaping([PeerId])->Signal<Never, NoError>, excludePeerIds: Set<PeerId> = Set()) {
        self.callback = callback
        self.contacts = contacts
        self.limitReachedText = limitReachedText
        super.init(context, excludePeerIds: excludePeerIds, defaultSelectedIds: defaultSelectedIds, additionTopItems: additionTopItems, limit: limit)
    }
    
    public override var selectTopics: Bool {
        return false
    }
    
    public override var hasFolders: Bool {
        return false
    }
    
    public override var hasCaptionView: Bool {
        return false
    }
    public override var blockCaptionView: Bool {
        return true
    }
    
    public override func statusStyle(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> ControlStyle {
        return ControlStyle(font: .normal(.text), foregroundColor: theme.colors.grayText)
    }
    
    public override func statusString(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> String? {
        if peer.id.namespace._internalGetInt32Value() == ChatListFilterPeerCategories.Namespace {
            return nil
        }
        if contacts.contains(peer.id) {
            return strings().businessMessageContact
        } else {
            return strings().businessMessageNonContact
        }
    }
    
    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars: [PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return callback(peerIds) |> castError(String.self)
    }
    public override func limitReached() {
        alert(for: context.window, info: limitReachedText)
    }
    public override var searchPlaceholderKey: String {
        return "ChatList.Add.Placeholder"
    }
    public override var interactionOk: String {
        return strings().chatListFilterAddDone
    }
    public override var alwaysEnableDone: Bool {
        return true
    }
    public override func possibilityPerformTo(_ peer: Peer) -> Bool {
        if peer is TelegramSecretChat {
            return false
        }
        if excludePeerIds.contains(peer.id) {
            return false
        }
        return peer.isUser && !peer.isBot
    }
    
}
