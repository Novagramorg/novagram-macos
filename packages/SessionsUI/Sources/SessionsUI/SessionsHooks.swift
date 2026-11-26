import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import LocalAnimations
import GeneralRows

public struct SessionsHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, [String]?) -> TableRowItem

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, [String]?) -> TableRowItem) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
    }

    private static var _shared: SessionsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: SessionsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("SessionsHooks.install must be called before sessions screens are used")
        return .placeholder
    }

    public static func install(_ hooks: SessionsHooks) {
        assert(Thread.isMainThread, "SessionsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = SessionsHooks(makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    })
}
