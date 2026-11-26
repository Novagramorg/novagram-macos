import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AffiliateUI

func installAffiliateUIHooks() {
    installAffiliateHooks(.init(openPeerInfo: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId)
    }, makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }))
}

extension MediaAnimatedStickerView: @retroactive AffiliateStickerView {
    public func updateAffiliateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, animated: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: file, size: size, context: context, table: nil, animated: animated)
    }
}
