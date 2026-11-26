import Cocoa
import TGUIKit
import TelegramTheme

public struct LiteModeHooks {
    public let updateTheme: (TelegramPresentationTheme, Bool) -> Void

    public init(updateTheme: @escaping (TelegramPresentationTheme, Bool) -> Void) {
        self.updateTheme = updateTheme
    }

    private static var _shared: LiteModeHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: LiteModeHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("LiteModeHooks.install must be called before the power saving screen is used")
        return .placeholder
    }

    public static func install(_ hooks: LiteModeHooks) {
        assert(Thread.isMainThread, "LiteModeHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = LiteModeHooks(
        updateTheme: { _, _ in }
    )
}
