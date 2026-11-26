import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import LocationUI
import InputView

public struct NewPollSchedule {
    public var date: Date
    public var repeatPeriod: Int32?

    public init(date: Date, repeatPeriod: Int32?) {
        self.date = date
        self.repeatPeriod = repeatPeriod
    }
}

public protocol NewPollChatInteraction: LocationChatInteraction {
    var pollContext: (any AccountContextProtocol) { get }
    var pollPeerId: PeerId { get }
    var pollMainPeer: Peer? { get }
    func sendPollMedias(_ medias: [Media], _ caption: ChatTextInputState, _ isCollage: Bool, _ additionText: ChatTextInputState?, _ silent: Bool, _ atDate: NewPollSchedule?, _ isSpoiler: Bool, _ messageEffect: AvailableMessageEffects.MessageEffect?, _ leadingText: Bool)
    func appendPollOption(_ messageId: MessageId, _ option: TelegramMediaPollOption)
}

public struct PollResultsHooks {
    public let openPeerInfo: (any AccountContextProtocol, PeerId) -> Void
    public let makeStickersPicker: (any AccountContextProtocol, PeerId, any NewPollChatInteraction, @escaping (TelegramMediaFile) -> Void) -> ViewController
    public let generateMedia: (MediaSenderContainer, Account, Bool) -> Signal<(Media, String), NoError>

    public init(openPeerInfo: @escaping (any AccountContextProtocol, PeerId) -> Void,
                makeStickersPicker: @escaping (any AccountContextProtocol, PeerId, any NewPollChatInteraction, @escaping (TelegramMediaFile) -> Void) -> ViewController,
                generateMedia: @escaping (MediaSenderContainer, Account, Bool) -> Signal<(Media, String), NoError>) {
        self.openPeerInfo = openPeerInfo
        self.makeStickersPicker = makeStickersPicker
        self.generateMedia = generateMedia
    }

    private static var _shared: PollResultsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PollResultsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PollResultsHooks.install must be called before the poll results screens are used")
        return .placeholder
    }

    public static func install(_ hooks: PollResultsHooks) {
        assert(Thread.isMainThread, "PollResultsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PollResultsHooks(
        openPeerInfo: { _, _ in },
        makeStickersPicker: { _, _, _, _ in ViewController() },
        generateMedia: { _, _, _ in .complete() }
    )
}
