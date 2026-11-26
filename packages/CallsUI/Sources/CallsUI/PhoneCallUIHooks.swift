import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramCallsCore
import PrivateCallScreen
import TelegramTheme

public protocol PhoneCallScreenHost: SharedAccountContextProtocol {
    var peerCall: PeerCallScreen? { get set }
}

public enum ConferenceCallJoinResult {
    case success(any GroupCallContextProtocol)
    case fail
    case samePeer(any GroupCallContextProtocol)
}

public struct PhoneCallUIHooks {
    public let callScreenHost: (any SharedAccountContextProtocol) -> (any PhoneCallScreenHost)?
    public let getCrossAccountCallSession: (any SharedAccountContextProtocol) -> PCallSession?
    public let getCrossAccountGroupCall: (any SharedAccountContextProtocol) -> (any GroupCallContextProtocol)?
    public let selectModalPeers: (Window, any AccountContextProtocol, String, Set<PeerId>) -> Signal<[PeerId], NoError>
    public let makeCallFeedbackController: (any AccountContextProtocol, CallId, Int, Bool, Bool) -> ModalViewController
    public let groupCallMinFullScreenSize: () -> NSSize
    public let makeGroupCallInviteLinkController: (any AccountContextProtocol, EngineCreatedGroupCall, TelegramPresentationTheme) -> ModalViewController
    public let requestOrJoinConferenceCall: (any AccountContextProtocol, GroupCallInfo, InternalGroupCallReference) -> Signal<ConferenceCallJoinResult, NoError>
    public let applyGroupCallResult: (any SharedAccountContextProtocol, any GroupCallContextProtocol) -> Void

    public init(callScreenHost: @escaping (any SharedAccountContextProtocol) -> (any PhoneCallScreenHost)?,
                getCrossAccountCallSession: @escaping (any SharedAccountContextProtocol) -> PCallSession?,
                getCrossAccountGroupCall: @escaping (any SharedAccountContextProtocol) -> (any GroupCallContextProtocol)?,
                selectModalPeers: @escaping (Window, any AccountContextProtocol, String, Set<PeerId>) -> Signal<[PeerId], NoError>,
                makeCallFeedbackController: @escaping (any AccountContextProtocol, CallId, Int, Bool, Bool) -> ModalViewController,
                groupCallMinFullScreenSize: @escaping () -> NSSize,
                makeGroupCallInviteLinkController: @escaping (any AccountContextProtocol, EngineCreatedGroupCall, TelegramPresentationTheme) -> ModalViewController,
                requestOrJoinConferenceCall: @escaping (any AccountContextProtocol, GroupCallInfo, InternalGroupCallReference) -> Signal<ConferenceCallJoinResult, NoError>,
                applyGroupCallResult: @escaping (any SharedAccountContextProtocol, any GroupCallContextProtocol) -> Void) {
        self.callScreenHost = callScreenHost
        self.getCrossAccountCallSession = getCrossAccountCallSession
        self.getCrossAccountGroupCall = getCrossAccountGroupCall
        self.selectModalPeers = selectModalPeers
        self.makeCallFeedbackController = makeCallFeedbackController
        self.groupCallMinFullScreenSize = groupCallMinFullScreenSize
        self.makeGroupCallInviteLinkController = makeGroupCallInviteLinkController
        self.requestOrJoinConferenceCall = requestOrJoinConferenceCall
        self.applyGroupCallResult = applyGroupCallResult
    }

    private static var _shared: PhoneCallUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PhoneCallUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PhoneCallUIHooks.install must be called before call screens are used")
        return .placeholder
    }

    public static func install(_ hooks: PhoneCallUIHooks) {
        assert(Thread.isMainThread, "PhoneCallUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PhoneCallUIHooks(callScreenHost: { _ in
        nil
    }, getCrossAccountCallSession: { _ in
        nil
    }, getCrossAccountGroupCall: { _ in
        nil
    }, selectModalPeers: { _, _, _, _ in
        .single([])
    }, makeCallFeedbackController: { _, _, _, _, _ in
        ModalViewController()
    }, groupCallMinFullScreenSize: {
        NSMakeSize(700, 540)
    }, makeGroupCallInviteLinkController: { _, _, _ in
        ModalViewController()
    }, requestOrJoinConferenceCall: { _, _, _ in
        .single(.fail)
    }, applyGroupCallResult: { _, _ in
    })
}
