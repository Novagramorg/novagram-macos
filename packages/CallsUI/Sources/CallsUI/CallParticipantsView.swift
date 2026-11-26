import AppKit
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import AvatarUI
import TelegramTheme

internal final class CallParticipantsView : View {
    
    private var avatars:[AvatarContentView] = []
    private let avatarsContainer = View(frame: NSMakeRect(0, 0, 24 * 3, 24))

    private(set) var peers:[Avatar] = []
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(avatarsContainer)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(participants: [EnginePeer], account: Account, animated: Bool) {
        
        
        
        
        
        let peers:[Avatar] = participants.prefix(3).reduce([], { current, value in
            var current = current
            current.append(.init(peer: value._asPeer(), index: current.count))
            return current
        })
                
        let photoSize = NSMakeSize(24, 24)

        applyAvatarStack(peers, current: &self.peers, avatars: &avatars, avatarsContainer: avatarsContainer, photoSize: photoSize, animated: animated, makeControl: { avatar in
            AvatarContentView(account: account, peer: avatar.peer, message: nil, synchronousLoad: false, size: photoSize, inset: 15)
        })
        self.avatarsContainer.setFrameSize(avatarsContainer.subviewsWidthSize)
        
        
        self.setFrameSize(avatarsContainer.subviewsWidthSize)
                    
    }
    
    public override func layout() {
        super.layout()
        self.avatarsContainer.frame = bounds
    }
}
