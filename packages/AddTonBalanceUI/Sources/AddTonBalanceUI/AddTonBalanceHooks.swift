import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import LocalAnimations
import GeneralRows

public struct AddTonBalanceHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
    }

    private static var _shared: AddTonBalanceHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: AddTonBalanceHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("AddTonBalanceHooks.install must be called before the add TON balance screen is used")
        return .placeholder
    }

    public static func install(_ hooks: AddTonBalanceHooks) {
        assert(Thread.isMainThread, "AddTonBalanceHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = AddTonBalanceHooks(
        makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
            GeneralRowItem(initialSize, stableId: stableId) }
    )
}
