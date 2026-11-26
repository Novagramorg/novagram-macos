import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import AvatarUI

public struct GiveawayChannel {
    public let peer: Peer
    public let text: TextViewLayout
    
    public var size: NSSize {
        return NSMakeSize(1 + 18 + 5 + text.layoutSize.width + 5, 20)
    }
    public var rect: NSRect

    public init(peer: Peer, text: TextViewLayout, rect: NSRect) {
        self.peer = peer
        self.text = text
        self.rect = rect
    }
}

public final class GiveawayChannelView : Control {
    private var channel: GiveawayChannel?
    private var open: ((PeerId)->Void)?
    private let avatar = AvatarControl(font: .avatar(7))
    private let textView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(avatar)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        avatar.setFrameSize(NSMakeSize(18, 18))
        avatar.userInteractionEnabled = false
        scaleOnClick = true
        
        self.set(handler: { [weak self] _ in
            if let channel = self?.channel {
                self?.open?(channel.peer.id)
            }
        }, for: .Click)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(_ channel: GiveawayChannel, context: any AccountContextProtocol, open: @escaping(PeerId)->Void) {
        self.channel = channel
        self.open = open
        self.avatar.setPeer(account: context.account, peer: channel.peer)
        self.textView.update(channel.text)
        
        let color = context.peerNameColors.get(channel.peer.namePeerColor ?? .blue)
        
        self.backgroundColor = color.main.withAlphaComponent(0.2)
        self.setFrameSize(channel.size)
        self.layer?.cornerRadius = frame.height / 2
    }
    
    public override func layout() {
        super.layout()
        avatar.centerY(x: 1)
        textView.centerY(x: avatar.frame.maxX + 5)
    }
}
