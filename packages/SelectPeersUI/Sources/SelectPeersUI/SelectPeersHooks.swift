import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramUtils
import LocalAnimations

public protocol SelectBotRequestStickerView: View {
    func updateSelectBotRequestSticker(sticker: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool)
}

public struct SelectPeersHooks {
    public let makeStickerView: (NSRect) -> SelectBotRequestStickerView
    public let stringForRight: (TelegramChatAdminRightsFlags, Bool, TelegramChatBannedRights?) -> String
    public let makeCreateBotModalController: (any AccountContextProtocol, String, String, String?, @escaping (PeerId?) -> Void) -> ModalViewController
    public let createGroupDirectly: (any AccountContextProtocol, [PeerId], CreateGroupRequires, @escaping (PeerId) -> Void) -> Void
    public let makeCreateChannelController: (any AccountContextProtocol, CreateChannelRequires, @escaping (PeerId, Bool) -> Void) -> ViewController
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void

    public init(makeStickerView: @escaping (NSRect) -> SelectBotRequestStickerView,
                stringForRight: @escaping (TelegramChatAdminRightsFlags, Bool, TelegramChatBannedRights?) -> String,
                makeCreateBotModalController: @escaping (any AccountContextProtocol, String, String, String?, @escaping (PeerId?) -> Void) -> ModalViewController,
                createGroupDirectly: @escaping (any AccountContextProtocol, [PeerId], CreateGroupRequires, @escaping (PeerId) -> Void) -> Void,
                makeCreateChannelController: @escaping (any AccountContextProtocol, CreateChannelRequires, @escaping (PeerId, Bool) -> Void) -> ViewController,
                navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void) {
        self.makeStickerView = makeStickerView
        self.stringForRight = stringForRight
        self.makeCreateBotModalController = makeCreateBotModalController
        self.createGroupDirectly = createGroupDirectly
        self.makeCreateChannelController = makeCreateChannelController
        self.navigateToChat = navigateToChat
    }

    private static var _shared: SelectPeersHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: SelectPeersHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("SelectPeersHooks.install must be called before the bot peer request screens are used")
        return .placeholder
    }

    public static func install(_ hooks: SelectPeersHooks) {
        assert(Thread.isMainThread, "SelectPeersHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = SelectPeersHooks(makeStickerView: { frame in
        SelectBotRequestPlaceholderStickerView(frame: frame)
    }, stringForRight: { _, _, _ in
        ""
    }, makeCreateBotModalController: { _, _, _, _, _ in
        ModalViewController()
    }, createGroupDirectly: { _, _, _, _ in
    }, makeCreateChannelController: { _, _, _ in
        ViewController()
    }, navigateToChat: { _, _, _ in
    })
}

private final class SelectBotRequestPlaceholderStickerView: View, SelectBotRequestStickerView {
    func updateSelectBotRequestSticker(sticker: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {

    }
}
