import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CallsUI
import PrivateCallScreen
import TelegramCallsCore

extension SharedAccountContext: PhoneCallScreenHost {

}

func installPhoneCallUIHooks() {
    PhoneCallUIHooks.install(PhoneCallUIHooks(callScreenHost: { sharedContext in
        return sharedContext.concrete
    }, getCrossAccountCallSession: { sharedContext in
        return sharedContext.concrete.getCrossAccountCallSession()
    }, getCrossAccountGroupCall: { sharedContext in
        return sharedContext.concrete.getCrossAccountGroupCall()
    }, selectModalPeers: { window, context, title, selectedPeerIds in
        return selectModalPeers(window: window, context: context.concrete, title: title, selectedPeerIds: selectedPeerIds)
    }, makeCallFeedbackController: { context, callId, starsCount, userInitiated, isVideo in
        return CallFeedbackController(context: context.concrete, callId: callId, starsCount: starsCount, userInitiated: userInitiated, isVideo: isVideo)
    }, groupCallMinFullScreenSize: {
        return GroupCallTheme.minFullScreenSize
    }, makeGroupCallInviteLinkController: { context, groupCall, presentation in
        return GroupCallInviteLinkController(context: context.concrete, source: .groupCall(groupCall), mode: .basic, presentation: presentation)
    }, requestOrJoinConferenceCall: { context, initialInfo, reference in
        return requestOrJoinConferenceCall(context: context.concrete, initialInfo: initialInfo, reference: reference) |> map { result -> ConferenceCallJoinResult in
            switch result {
            case let .success(callContext):
                return .success(callContext)
            case .fail:
                return .fail
            case let .samePeer(callContext):
                return .samePeer(callContext)
            }
        }
    }, applyGroupCallResult: { sharedContext, callContext in
        guard let callContext = callContext as? GroupCallContext else {
            return
        }
        applyGroupCallResult(sharedContext.concrete, callContext)
    }))
}
