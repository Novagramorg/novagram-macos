import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramCallsCore
import TelegramMediaUtils
import TgVoipWebrtc

func installCallsCoreUIHooks() {
    installCallsCoreHooks(.init(presentUpgradedConferenceCall: { sharedContext, conferenceCall, accountContext, window in
        guard let sharedContext = sharedContext as? SharedAccountContext, let accountContext = accountContext as? AccountContext else {
            return
        }
        let callContext = GroupCallContext(call: conferenceCall, peerMemberContextsManager: accountContext.peerChannelMemberCategoriesContextsManager, window: window)
        sharedContext.dropCrossCall()
        sharedContext.peerCall?.contextObject = nil
        sharedContext.peerCall?.onCompletion?()
        applyGroupCallResult(sharedContext, callContext)
    }, presentScreenCapturePicker: { devices, microIsOff, select in
        return presentDesktopCapturerWindow(mode: .screencast, select: { source, value in
            select(source, value)
        }, devices: devices, microIsOff: microIsOff)
    }, showCall: { session in
        appDelegate?.sharedApplicationContextValue?.sharedContext.showCall(with: session)
    }, accountContext: { recordId in
        return appDelegate?.accountContext(for: recordId)
    }, activeWindow: {
        return appDelegate?.activeContext(for: nil)?.window
    }, cachedGroupCallContexts: { context in
        guard let context = context as? AccountContext else {
            preconditionFailure("cachedGroupCallContexts requires a concrete AccountContext")
        }
        return context.cachedGroupCallContexts
    }, devicesContext: { sharedContext in
        guard let sharedContext = sharedContext as? SharedAccountContext else {
            preconditionFailure("devicesContext requires a concrete SharedAccountContext")
        }
        return sharedContext.devicesContext
    }, alert: { window, info in
        alert(for: window, info: info)
    }, verifyAlert: { window, information, ok, cancel, option, handler in
        verifyAlert_button(for: window, information: information, ok: ok, cancel: cancel, option: option, successHandler: { result in
            if case .thrid = result {
                handler(true)
            } else {
                handler(false)
            }
        })
    }))
}

extension AccountContextProtocol {
    var concrete: AccountContext {
        guard let value = self as? AccountContext else {
            preconditionFailure("call packages are always driven by a concrete AccountContext")
        }
        return value
    }
}

extension SharedAccountContextProtocol {
    var concrete: SharedAccountContext {
        guard let value = self as? SharedAccountContext else {
            preconditionFailure("call packages are always driven by a concrete SharedAccountContext")
        }
        return value
    }
}
