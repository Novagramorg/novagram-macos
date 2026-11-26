import Foundation
import SwiftSignalKit
import TelegramContext
import TelegramCore

public struct WalletUIHooks {
    public var appPasslock: () -> Signal<Bool, NoError> = { .single(false) }
    public var openTonEarnings: (any AccountContextProtocol) -> Void = { _ in }

    public var openGiftVariants: (any AccountContextProtocol, StarGift.UniqueGift, String) -> Void = { _, _, _ in }

    public init() {}

    private static var installed: WalletUIHooks?

    public static var shared: WalletUIHooks {
        return installed ?? WalletUIHooks()
    }

    public static var isInstalled: Bool {
        return installed != nil
    }

    public static func install(_ hooks: WalletUIHooks) {
        installed = hooks
    }
}

func walletUIPasscodeLocked() -> Signal<Bool, NoError> {
    return WalletUIHooks.shared.appPasslock()
}
