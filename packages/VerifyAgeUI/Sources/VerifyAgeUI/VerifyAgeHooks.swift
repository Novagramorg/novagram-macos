import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import LocalAnimations
import GeneralRows

public struct VerifyAgeHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
    }

    private static var _shared: VerifyAgeHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: VerifyAgeHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("VerifyAgeHooks.install must be called before the age verification screen is used")
        return .placeholder
    }

    public static func install(_ hooks: VerifyAgeHooks) {
        assert(Thread.isMainThread, "VerifyAgeHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = VerifyAgeHooks(
        makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
            GeneralRowItem(initialSize, stableId: stableId) }
    )
}
