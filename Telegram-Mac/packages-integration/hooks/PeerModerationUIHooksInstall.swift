import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import PeerModerationUI

func installPeerModerationUIHooks() {
    PeerModerationUIHooks.install(PeerModerationUIHooks(pushPeerInfo: { navigation, context, peerId in
        PeerInfoController.push(navigation: navigation, context: context as! AccountContext, peerId: peerId)
    }, makePeerInfoController: { context, peer in
        return PeerInfoController(context: context as! AccountContext, peer: peer)
    }))
}
