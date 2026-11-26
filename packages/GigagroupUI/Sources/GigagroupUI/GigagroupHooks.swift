import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import LocalAnimations
import GeneralRows

public struct GigagroupHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
    }

    private static var _shared: GigagroupHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: GigagroupHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("GigagroupHooks.install must be called before the gigagroup landing screen is used")
        return .placeholder
    }

    public static func install(_ hooks: GigagroupHooks) {
        assert(Thread.isMainThread, "GigagroupHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = GigagroupHooks(
        makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
            GeneralRowItem(initialSize, stableId: stableId) }
    )
}
