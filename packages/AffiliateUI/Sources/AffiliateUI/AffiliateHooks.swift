import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public protocol AffiliateStickerView: AnyObject {
    func updateAffiliateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, animated: Bool)
}

public struct AffiliateHooks {
    public let openPeerInfo: (any AccountContextProtocol, PeerId) -> Void
    public let makeStickerView: (NSRect) -> NSView

    public init(openPeerInfo: @escaping (any AccountContextProtocol, PeerId) -> Void,
                makeStickerView: @escaping (NSRect) -> NSView) {
        self.openPeerInfo = openPeerInfo
        self.makeStickerView = makeStickerView
    }

    private static var value: AffiliateHooks?

    public static var shared: AffiliateHooks {
        guard let value = value else {
            preconditionFailure("AffiliateHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: AffiliateHooks) {
        self.value = hooks
    }
}

public func installAffiliateHooks(_ hooks: AffiliateHooks) {
    AffiliateHooks.install(hooks)
}
