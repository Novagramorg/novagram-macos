import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramCallsCore
import TelegramContext
import TelegramMediaUtils
import GeneralRows
import TelegramTheme
import EntertainmentUI
import ChatModeTypes
import TelegramUtils

public protocol GroupCallEmojiesController: ViewController {

}

public struct GroupCallScreenUIHooks {
    public let forceUpdateStatusBarIconByDockTile: (any SharedAccountContextProtocol) -> Void
    public let getCrossAccountGroupCall: (any SharedAccountContextProtocol) -> GroupCallContext?
    public let updateCurrentGroupCallValue: (any SharedAccountContextProtocol, GroupCallContext?) -> Void
    public let showGroupCall: (any SharedAccountContextProtocol, GroupCallContext) -> Void
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let showReactionsWindow: (any AccountContextProtocol, PeerId, @escaping (StickerPackItem, NSRect?) -> Void, (() -> Void)?, TelegramPresentationTheme, String, Window?, NSView & StickerFramesCollector) -> Void
    public let makeVolumeMenuItem: (CGFloat, ((CGFloat, Bool) -> Void)?) -> ContextMenuItem
    public let generateFakeIconReversed: (NSColor, NSColor) -> CGImage
    public let generateScamIconReversed: (NSColor, NSColor) -> CGImage
    public let makeEmojies: (any AccountContextProtocol, TelegramPresentationTheme) -> GroupCallEmojiesController
    public let updateEmojies: (GroupCallEmojiesController, EntertainmentInteractions, any ChatInteractionProtocol) -> Void
    public let formatMessageText: ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, NSColor, NSColor) -> NSAttributedString
    public let reactionsListWidth: (Int, Int, Bool) -> CGFloat
    public let makeReactionsListView: (NSRect, any AccountContextProtocol, [ContextReaction], @escaping (MessageReaction.Reaction, Bool, NSRect?) -> Void, ((NSView & StickerFramesCollector) -> Void)?, TelegramPresentationTheme, Window?) -> NSView
    public let makeRTMPServerUrlItem: (NSSize, AnyHashable, String, String, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont) -> TableRowItem
    public let makeRTMPStreamKeyItem: (NSSize, AnyHashable, String, String, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont, Bool?, (() -> Void)?) -> TableRowItem
    public let makeSettingsRTMPServerUrlItem: (NSSize, AnyHashable, String, String, NSColor, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont, NSColor, NSColor) -> TableRowItem
    public let makeSettingsRTMPStreamKeyItem: (NSSize, AnyHashable, String, String, NSColor, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont, Bool?, (() -> Void)?, NSColor, NSColor) -> TableRowItem
    public let groupCallContext: (any SharedAccountContextProtocol) -> Signal<GroupCallContext?, NoError>
    public let cachedGroupCallContexts: (any AccountContextProtocol) -> AccountGroupCallContextCacheImpl

    public init(forceUpdateStatusBarIconByDockTile: @escaping (any SharedAccountContextProtocol) -> Void,
                getCrossAccountGroupCall: @escaping (any SharedAccountContextProtocol) -> GroupCallContext?,
                updateCurrentGroupCallValue: @escaping (any SharedAccountContextProtocol, GroupCallContext?) -> Void,
                showGroupCall: @escaping (any SharedAccountContextProtocol, GroupCallContext) -> Void,
                pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                showReactionsWindow: @escaping (any AccountContextProtocol, PeerId, @escaping (StickerPackItem, NSRect?) -> Void, (() -> Void)?, TelegramPresentationTheme, String, Window?, NSView & StickerFramesCollector) -> Void,
                makeVolumeMenuItem: @escaping (CGFloat, ((CGFloat, Bool) -> Void)?) -> ContextMenuItem,
                generateFakeIconReversed: @escaping (NSColor, NSColor) -> CGImage,
                generateScamIconReversed: @escaping (NSColor, NSColor) -> CGImage,
                makeEmojies: @escaping (any AccountContextProtocol, TelegramPresentationTheme) -> GroupCallEmojiesController,
                updateEmojies: @escaping (GroupCallEmojiesController, EntertainmentInteractions, any ChatInteractionProtocol) -> Void,
                formatMessageText: @escaping ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, NSColor, NSColor) -> NSAttributedString,
                reactionsListWidth: @escaping (Int, Int, Bool) -> CGFloat,
                makeReactionsListView: @escaping (NSRect, any AccountContextProtocol, [ContextReaction], @escaping (MessageReaction.Reaction, Bool, NSRect?) -> Void, ((NSView & StickerFramesCollector) -> Void)?, TelegramPresentationTheme, Window?) -> NSView,
                makeRTMPServerUrlItem: @escaping (NSSize, AnyHashable, String, String, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont) -> TableRowItem,
                makeRTMPStreamKeyItem: @escaping (NSSize, AnyHashable, String, String, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont, Bool?, (() -> Void)?) -> TableRowItem,
                makeSettingsRTMPServerUrlItem: @escaping (NSSize, AnyHashable, String, String, NSColor, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont, NSColor, NSColor) -> TableRowItem,
                makeSettingsRTMPStreamKeyItem: @escaping (NSSize, AnyHashable, String, String, NSColor, NSColor, NSColor, String, (any AccountContextProtocol)?, GeneralViewType, Bool, @escaping () -> Void, Bool, Bool, (() -> Void)?, NSFont, Bool?, (() -> Void)?, NSColor, NSColor) -> TableRowItem,
                groupCallContext: @escaping (any SharedAccountContextProtocol) -> Signal<GroupCallContext?, NoError>,
                cachedGroupCallContexts: @escaping (any AccountContextProtocol) -> AccountGroupCallContextCacheImpl) {
        self.forceUpdateStatusBarIconByDockTile = forceUpdateStatusBarIconByDockTile
        self.getCrossAccountGroupCall = getCrossAccountGroupCall
        self.updateCurrentGroupCallValue = updateCurrentGroupCallValue
        self.showGroupCall = showGroupCall
        self.pushPeerInfo = pushPeerInfo
        self.showReactionsWindow = showReactionsWindow
        self.makeVolumeMenuItem = makeVolumeMenuItem
        self.generateFakeIconReversed = generateFakeIconReversed
        self.generateScamIconReversed = generateScamIconReversed
        self.makeEmojies = makeEmojies
        self.updateEmojies = updateEmojies
        self.formatMessageText = formatMessageText
        self.reactionsListWidth = reactionsListWidth
        self.makeReactionsListView = makeReactionsListView
        self.makeRTMPServerUrlItem = makeRTMPServerUrlItem
        self.makeRTMPStreamKeyItem = makeRTMPStreamKeyItem
        self.makeSettingsRTMPServerUrlItem = makeSettingsRTMPServerUrlItem
        self.makeSettingsRTMPStreamKeyItem = makeSettingsRTMPStreamKeyItem
        self.groupCallContext = groupCallContext
        self.cachedGroupCallContexts = cachedGroupCallContexts
    }

    private static var _shared: GroupCallScreenUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: GroupCallScreenUIHooks {
        if let value = _shared {
            return value
        }
        preconditionFailure("GroupCallScreenUIHooks.install must be called before group call screens are used")
    }

    public static func install(_ hooks: GroupCallScreenUIHooks) {
        assert(Thread.isMainThread, "GroupCallScreenUIHooks.install must be called on the main thread")
        _shared = hooks
    }
}
