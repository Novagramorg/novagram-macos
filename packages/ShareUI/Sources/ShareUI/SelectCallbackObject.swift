import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import AlertsUI
import TelegramContext
import TelegramUtils
import InputView
import ChatModeTypes
import InputDataUI

public class SelectCallbackObject : ShareObject {
    private let callback:([PeerId])->Signal<Never, NoError>
    private let limitReachedText: String
    public init(_ context: any AccountContextProtocol, defaultSelectedIds: Set<PeerId>, additionTopItems: ShareAdditionItems?, limit: Int?, limitReachedText: String, callback:@escaping([PeerId])->Signal<Never, NoError>, excludePeerIds: Set<PeerId> = Set()) {
        self.callback = callback
        self.limitReachedText = limitReachedText
        super.init(context, excludePeerIds: excludePeerIds, defaultSelectedIds: defaultSelectedIds, additionTopItems: additionTopItems, limit: limit)
    }

    public override var selectTopics: Bool {
        return false
    }
    public override var canSelectCommunity: Bool {
        return true
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


    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars: [PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return callback(peerIds) |> castError(String.self)
    }
    public override func limitReached() {
        if !context.isPremium {
            FeatureNavigationHooks.shared.showPremiumLimit(context, .chatInFolders)
        } else {
            alert(for: context.window, info: limitReachedText)
        }
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
        return true
    }

}
