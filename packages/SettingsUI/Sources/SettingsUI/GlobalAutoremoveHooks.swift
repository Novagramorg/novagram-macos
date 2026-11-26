import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import LocalAnimations
import GeneralRows

public struct GlobalAutoremoveHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem
    public let showApplyToExisting: (any AccountContextProtocol, Int32, @escaping ([PeerId]) -> Signal<Never, NoError>) -> Void

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem,
                showApplyToExisting: @escaping (any AccountContextProtocol, Int32, @escaping ([PeerId]) -> Signal<Never, NoError>) -> Void) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.showApplyToExisting = showApplyToExisting
    }

    private static var _shared: GlobalAutoremoveHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: GlobalAutoremoveHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("GlobalAutoremoveHooks.install must be called before the auto-delete screens are used")
        return .placeholder
    }

    public static func install(_ hooks: GlobalAutoremoveHooks) {
        assert(Thread.isMainThread, "GlobalAutoremoveHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = GlobalAutoremoveHooks(
        makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
            GeneralRowItem(initialSize, stableId: stableId) },
        showApplyToExisting: { _, _, _ in }
    )
}
