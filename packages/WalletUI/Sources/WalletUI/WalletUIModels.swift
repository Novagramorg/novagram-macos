import TelegramContext
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit

func walletUIPeerView(peerId: PeerId, postbox: Postbox) -> Signal<Peer?, NoError> {
    return postbox.combinedView(keys: [.basicPeer(peerId)]) |> map { view in
        return (view.views[.basicPeer(peerId)] as? BasicPeerView)?.peer
    }
}

func walletUIWindow(_ context: any AccountContextProtocol, _ controller: ViewController?) -> Window {
    return controller?.window ?? context.window
}
