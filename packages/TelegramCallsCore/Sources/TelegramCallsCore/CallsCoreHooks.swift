import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramMediaUtils
import TgVoipWebrtc
import AVFoundation
import SystemPermissions
import ProxyUtils

public struct CallsCoreHooks {
    public let presentUpgradedConferenceCall: (any SharedAccountContextProtocol, PresentationGroupCallImpl, any AccountContextProtocol, Window) -> Void
    public let presentScreenCapturePicker: (DevicesContext, Bool, @escaping (VideoSourceMac, Bool) -> Void) -> NSWindow?
    public let showCall: (PCallSession) -> Void
    public let accountContext: (AccountRecordId) -> (any AccountContextProtocol)?
    public let activeWindow: () -> Window?
    public let cachedGroupCallContexts: (any AccountContextProtocol) -> AccountGroupCallContextCacheImpl
    public let devicesContext: (any SharedAccountContextProtocol) -> DevicesContext
    public let alert: (Window, String) -> Void
    public let verifyAlert: (Window, String, String, String, String?, @escaping (Bool) -> Void) -> Void

    public init(presentUpgradedConferenceCall: @escaping (any SharedAccountContextProtocol, PresentationGroupCallImpl, any AccountContextProtocol, Window) -> Void,
                presentScreenCapturePicker: @escaping (DevicesContext, Bool, @escaping (VideoSourceMac, Bool) -> Void) -> NSWindow?,
                showCall: @escaping (PCallSession) -> Void,
                accountContext: @escaping (AccountRecordId) -> (any AccountContextProtocol)?,
                activeWindow: @escaping () -> Window?,
                cachedGroupCallContexts: @escaping (any AccountContextProtocol) -> AccountGroupCallContextCacheImpl,
                devicesContext: @escaping (any SharedAccountContextProtocol) -> DevicesContext,
                alert: @escaping (Window, String) -> Void,
                verifyAlert: @escaping (Window, String, String, String, String?, @escaping (Bool) -> Void) -> Void) {
        self.presentUpgradedConferenceCall = presentUpgradedConferenceCall
        self.presentScreenCapturePicker = presentScreenCapturePicker
        self.showCall = showCall
        self.accountContext = accountContext
        self.activeWindow = activeWindow
        self.cachedGroupCallContexts = cachedGroupCallContexts
        self.devicesContext = devicesContext
        self.alert = alert
        self.verifyAlert = verifyAlert
    }

    private static var value: CallsCoreHooks?

    public static var shared: CallsCoreHooks {
        guard let value = value else {
            preconditionFailure("CallsCoreHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: CallsCoreHooks) {
        self.value = hooks
    }
}

public func installCallsCoreHooks(_ hooks: CallsCoreHooks) {
    CallsCoreHooks.install(hooks)
}
