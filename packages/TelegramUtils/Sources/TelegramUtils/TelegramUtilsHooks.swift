import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMediaResources
import InAppSettings

public struct TelegramUtilsHooks {
    public let animationsAreLite: () -> Bool
    public let isLite: (LiteModeKey) -> Bool
    public let peerTitle: (Peer) -> String
    public let peerLetters: (Peer) -> [String]
    public let peerIsForum: (Peer) -> Bool
    public let peerCompactTitle: (Peer) -> String
    public let repliesPeerId: () -> PeerId
    public let topicFile: ((String, Int32, Bool) -> TelegramMediaFile)?
    public let topicImage: ((String, [NSColor], [NSColor]) -> Signal<ImageDataTransformation, NoError>)?
    public let generalTopicImage: ((LocalBundleResource, CGFloat) -> Signal<ImageDataTransformation, NoError>)?

    public init(animationsAreLite: @escaping () -> Bool, isLite: @escaping (LiteModeKey) -> Bool, peerTitle: @escaping (Peer) -> String, peerLetters: @escaping (Peer) -> [String], peerIsForum: @escaping (Peer) -> Bool, peerCompactTitle: @escaping (Peer) -> String, repliesPeerId: @escaping () -> PeerId, topicFile: ((String, Int32, Bool) -> TelegramMediaFile)? = nil, topicImage: ((String, [NSColor], [NSColor]) -> Signal<ImageDataTransformation, NoError>)? = nil, generalTopicImage: ((LocalBundleResource, CGFloat) -> Signal<ImageDataTransformation, NoError>)? = nil) {
        self.animationsAreLite = animationsAreLite
        self.isLite = isLite
        self.peerTitle = peerTitle
        self.peerLetters = peerLetters
        self.peerIsForum = peerIsForum
        self.peerCompactTitle = peerCompactTitle
        self.repliesPeerId = repliesPeerId
        self.topicFile = topicFile
        self.topicImage = topicImage
        self.generalTopicImage = generalTopicImage
    }

    private static var installed: TelegramUtilsHooks?

    public static var shared: TelegramUtilsHooks {
        guard let hooks = installed else {
            fatalError("TelegramUtilsHooks.install must be called before shared presentation is used")
        }
        return hooks
    }

    public static func install(_ hooks: TelegramUtilsHooks) {
        installed = hooks
    }
}
