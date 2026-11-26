import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import LocalAnimations
import GeneralRows

public protocol PasskeysStickerView: NSView {
    func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool)
}

public struct PasskeysHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem
    public let makeStickerView: () -> PasskeysStickerView
    public let callbackLink: (String, @escaping (String) -> Void) -> Any
    public let openAppealLink: (any AccountContextProtocol, String) -> Void

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem,
                makeStickerView: @escaping () -> PasskeysStickerView,
                callbackLink: @escaping (String, @escaping (String) -> Void) -> Any,
                openAppealLink: @escaping (any AccountContextProtocol, String) -> Void) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.makeStickerView = makeStickerView
        self.callbackLink = callbackLink
        self.openAppealLink = openAppealLink
    }

    private static var _shared: PasskeysHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PasskeysHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PasskeysHooks.install must be called before the passkeys and account freeze screens are used")
        return .placeholder
    }

    public static func install(_ hooks: PasskeysHooks) {
        assert(Thread.isMainThread, "PasskeysHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PasskeysHooks(
        makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
            GeneralRowItem(initialSize, stableId: stableId) },
        makeStickerView: { PasskeysPlaceholderStickerView(frame: .zero) },
        callbackLink: { _, _ in NSNull() },
        openAppealLink: { _, _ in }
    )
}

final class PasskeysPlaceholderStickerView: View, PasskeysStickerView {
    func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {

    }
}
