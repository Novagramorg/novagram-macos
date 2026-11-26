import Cocoa
import TelegramUtils
import InputView
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import InAppSettings
import TelegramContext
import TelegramTheme

public final class ShareAdditionItem {
    public let peer: Peer
    public let status: String?
    public init(peer: Peer, status: String?) {
        self.peer = peer
        self.status = status
    }
}

public final class ShareAdditionItems {
    public let items: [ShareAdditionItem]
    public let topSeparator: String
    public let bottomSeparator: String
    public let selectable: Bool
    public init(items: [ShareAdditionItem], topSeparator: String, bottomSeparator: String, selectable: Bool = true) {
        self.items = items
        self.topSeparator = topSeparator
        self.bottomSeparator = bottomSeparator
        self.selectable = selectable
    }
}


open class ShareObject {
    
    public let additionTopItems:ShareAdditionItems?
    public var presentation: TelegramPresentationTheme?
    public let context: any AccountContextProtocol
    public let emptyPerformOnClose: Bool
    public let excludePeerIds: Set<PeerId>
    public let defaultSelectedIds:Set<PeerId>
    public let limit: Int?
    
    open var appearance: TelegramPresentationTheme {
        return presentation ?? theme
    }
    
    open var messagesCount: Int {
        return 0
    }
    
    public var withoutSound: Bool = false
    public var scheduleDate: Date? = nil
    
    public var threadIds: [PeerId : Int64] = [:]
    
    public init(_ context:any AccountContextProtocol, emptyPerformOnClose: Bool = false, excludePeerIds:Set<PeerId> = [], defaultSelectedIds: Set<PeerId> = [], additionTopItems:ShareAdditionItems? = nil, limit: Int? = nil) {
        self.limit = limit
        self.context = context
        self.emptyPerformOnClose = emptyPerformOnClose
        self.excludePeerIds = excludePeerIds
        self.additionTopItems = additionTopItems
        self.defaultSelectedIds = defaultSelectedIds
    }
    
    open var multipleSelection: Bool {
        return true
    }
    open var hasCaptionView: Bool {
        return true
    }
    open var blockCaptionView: Bool {
        return false
    }
    open var interactionOk: String {
        return strings().modalOK
    }
    open var mutableSelection: Bool {
        return true
    }
    open var hasInteraction: Bool {
        return true
    }
    open var selectTopics: Bool {
        return true
    }
    open var canSelectCommunity: Bool {
        return false
    }
    
    open func attributes(_ peerId: PeerId, sendPaidMessageStars: StarsAmount?) -> [MessageAttribute] {
        var attributes:[MessageAttribute] = []
        if FastSettings.isChannelMessagesMuted(peerId) || withoutSound {
            attributes.append(NotificationInfoMessageAttribute(flags: [.muted]))
        }
        if let date = scheduleDate {
            attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: Int32(date.timeIntervalSince1970), repeatPeriod: nil))
        }
        if let sendPaidMessageStars = sendPaidMessageStars, peerId != context.peerId {
            attributes.append(PaidStarsMessageAttribute(stars: sendPaidMessageStars, postponeSending: false))
        }
        
        return attributes
    }
    
    open var searchPlaceholderKey: String {
        return "ShareModal.Search.Placeholder"
    }

    open var alwaysEnableDone: Bool {
        return false
    }
    
    open func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return .complete()
    }
    open func limitReached() {
        
    }
    
    open var successText: String {
        return "Success!"
    }
    
    open var hasLink: Bool {
        return false
    }
    open var hasFolders: Bool {
        return true
    }
    
    open func shareLink() {
        
    }
    
    open func possibilityPerformTo(_ peer:Peer) -> Bool {
        return peer.canSendMessage(false) && !self.excludePeerIds.contains(peer.id)
    }
    open func statusString(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> String? {
        return peer.id == context.peerId ? (multipleSelection ? nil : strings().forwardToSavedMessages) : presence?.status.string
    }
    open func statusStyle(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> ControlStyle {
        let color = presence?.status.string.isEmpty == false ? presence?.status.attribute(NSAttributedString.Key.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil
        let theme = presentation ?? theme
        return ControlStyle(font: .normal(.text), foregroundColor: peer.id == context.peerId ? theme.colors.grayText : color ?? theme.colors.grayText)
    }
}
