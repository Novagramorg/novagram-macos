#if SHARE
import TelegramUtilsShare
#else
import TelegramUtils
#endif
import TelegramTheme
import TelegramContext
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox

public final class InlineAvatarLayer: SimpleLayer {
    private var disposable: Disposable?
    public init(context: any AccountContextProtocol, frame: NSRect, peer: EnginePeer) {

        super.init()
        self.frame = frame
        let size = frame.size

        let signal: Signal<(CGImage?, Bool), NoError> = peerAvatarImage(account: context.account, photo: .peer(peer._asPeer(), peer._asPeer().smallProfileImage, peer._asPeer().namePeerColor, peer.displayLetters, nil, nil), displayDimensions: size, scale: System.backingScale, font: .avatar(size.height / 3 + 3), genCap: true, synchronousLoad: false) |> deliverOnMainQueue

        let disposable = signal.start(next: { [weak self] values in
            self?.contents = values.0
        })
        self.disposable = disposable
    }

    public override init(layer: Any) {
        super.init(layer: layer)
    }

    deinit {
        disposable?.dispose()
    }

    public required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
