import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramContext
import GeneralRows

public struct ChatPanelsHooks {
    public let stringForGroupPermission: (TelegramChatBannedRightsFlags, TelegramChannel?) -> String
    public let groupPermissionDependencies: (TelegramChatBannedRightsFlags) -> TelegramChatBannedRightsFlags
    public let makeTextAndLabelItem: (NSSize, AnyHashable, String, String, String, any AccountContextProtocol, GeneralViewType, Bool, @escaping () -> Void) -> TableRowItem
    public let meUrlHost: (any AccountContextProtocol) -> String

    public init(stringForGroupPermission: @escaping (TelegramChatBannedRightsFlags, TelegramChannel?) -> String,
                groupPermissionDependencies: @escaping (TelegramChatBannedRightsFlags) -> TelegramChatBannedRightsFlags,
                makeTextAndLabelItem: @escaping (NSSize, AnyHashable, String, String, String, any AccountContextProtocol, GeneralViewType, Bool, @escaping () -> Void) -> TableRowItem,
                meUrlHost: @escaping (any AccountContextProtocol) -> String) {
        self.stringForGroupPermission = stringForGroupPermission
        self.groupPermissionDependencies = groupPermissionDependencies
        self.makeTextAndLabelItem = makeTextAndLabelItem
        self.meUrlHost = meUrlHost
    }

    private static var _shared: ChatPanelsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatPanelsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatPanelsHooks.install must be called before chat panels are used")
        return .placeholder
    }

    public static func install(_ hooks: ChatPanelsHooks) {
        assert(Thread.isMainThread, "ChatPanelsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatPanelsHooks(stringForGroupPermission: { _, _ in
        ""
    }, groupPermissionDependencies: { _ in
        []
    }, makeTextAndLabelItem: { initialSize, stableId, _, _, _, _, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    }, meUrlHost: { _ in
        ""
    })
}
