import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import LocalAnimations
import GeneralRows

public struct ChannelSettingsUIHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString) -> TableRowItem
    public let resolveUsername: (String, any AccountContextProtocol) -> Signal<Peer?, NoError>
    public let inputSource: (any AccountContextProtocol) -> InputSources
    public let enableBetaFeatures: () -> Bool

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString) -> TableRowItem,
                resolveUsername: @escaping (String, any AccountContextProtocol) -> Signal<Peer?, NoError>,
                inputSource: @escaping (any AccountContextProtocol) -> InputSources,
                enableBetaFeatures: @escaping () -> Bool) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.resolveUsername = resolveUsername
        self.inputSource = inputSource
        self.enableBetaFeatures = enableBetaFeatures
    }

    private static var _shared: ChannelSettingsUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChannelSettingsUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChannelSettingsUIHooks.install must be called before channel settings screens are used")
        return .placeholder
    }

    public static func install(_ hooks: ChannelSettingsUIHooks) {
        assert(Thread.isMainThread, "ChannelSettingsUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChannelSettingsUIHooks(makeStickerHeaderItem: { initialSize, stableId, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    }, resolveUsername: { _, _ in
        .single(nil)
    }, inputSource: { _ in
        InputSources()
    }, enableBetaFeatures: {
        false
    })
}
