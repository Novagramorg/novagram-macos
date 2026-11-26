import Cocoa
import TelegramCallsCore
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import AvatarUI
import Localization
import TelegramContext

public final class GroupCallIncomingView : Control {
    
    private final class ParticipantsView : View {
        private let textView: TextView = TextView()
        
        private var avatars:[AvatarContentView] = []
        private let avatarsContainer = View(frame: NSMakeRect(0, 0, 24 * 3, 24))

        private var peers:[Avatar] = []
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            addSubview(avatarsContainer)
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(participants: [EnginePeer], context: any AccountContextProtocol, animated: Bool) {
            
            
            
            let duration = Double(0.2)
            let timingFunction = CAMediaTimingFunctionName.easeOut
            
            
            let peers:[Avatar] = participants.prefix(3).reduce([], { current, value in
                var current = current
                current.append(.init(peer: value._asPeer(), index: current.count))
                return current
            })
                    
            let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: self.peers, rightList: peers)
            
            let photoSize = NSMakeSize(24, 24)
            
            for removed in removed.reversed() {
                let control = avatars.remove(at: removed)
                let peer = self.peers[removed]
                let haveNext = peers.contains(where: { $0.stableId == peer.stableId })
                control.updateLayout(size: photoSize, isClipped: false, animated: animated)
                if animated && !haveNext {
                    control.layer?.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak control] _ in
                        control?.removeFromSuperview()
                    })
                    control.layer?.animateScaleSpring(from: 1.0, to: 0.2, duration: duration)
                } else {
                    control.removeFromSuperview()
                }
            }
            for inserted in inserted {
                let control = AvatarContentView(context: context, peer: inserted.1.peer, message: nil, synchronousLoad: false, size: photoSize, inset: 15)
                control.updateLayout(size: photoSize, isClipped: inserted.0 != 0, animated: animated)
                control.userInteractionEnabled = false
                control.setFrameSize(photoSize)
                control.setFrameOrigin(NSMakePoint(CGFloat(inserted.0) * (photoSize.width - 20), 0))
                avatars.insert(control, at: inserted.0)
                avatarsContainer.subviews.insert(control, at: inserted.0)
                if animated {
                    if let index = inserted.2 {
                        control.layer?.animatePosition(from: NSMakePoint(CGFloat(index) * (photoSize.width - 18), 0), to: control.frame.origin, timingFunction: timingFunction)
                    } else {
                        control.layer?.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: timingFunction)
                        control.layer?.animateScaleSpring(from: 0.2, to: 1.0, duration: duration)
                    }
                }
            }
            for updated in updated {
                let control = avatars[updated.0]
                control.updateLayout(size: photoSize, isClipped: updated.0 != 0, animated: animated)
                let updatedPoint = NSMakePoint(CGFloat(updated.0) * (photoSize.width - 20), 0)
                if animated {
                    control.layer?.animatePosition(from: control.frame.origin - updatedPoint, to: .zero, duration: duration, timingFunction: timingFunction, additive: true)
                }
                control.setFrameOrigin(updatedPoint)
            }
            var index: CGFloat = 10
            for control in avatarsContainer.subviews.compactMap({ $0 as? AvatarContentView }) {
                control.layer?.zPosition = index
                index -= 1
            }
            
            self.peers = peers
            self.avatarsContainer.setFrameSize(avatarsContainer.subviewsWidthSize)
            
            let textLayout = TextViewLayout(.initialize(string: strings().chatGroupCallMembersOther(participants.count), color: GroupCallTheme.titleColor, font: .medium(.text)))
            
            textLayout.measure(width: .greatestFiniteMagnitude)
            
            self.textView.update(textLayout)
            
            
            self.setFrameSize(NSMakeSize(3 + avatarsContainer.frame.width + 3 + textLayout.layoutSize.width + 3, 30))
            
            layer?.cornerRadius = frame.height / 2
            
                        
        }
        
        override func layout() {
            super.layout()
            
            let avatarRect = self.bounds.focusY(avatarsContainer.subviewsWidthSize, x: 3)
            self.avatarsContainer.frame = avatarRect
            
            self.textView.centerY(x: self.avatarsContainer.frame.maxX + 3)
        }
    }
    
    private let avatar = AvatarControl(font: .avatar(30))
    private let headerView = TextView()
    private let infoView = TextView()
    private let participantsView = ParticipantsView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(avatar)
        addSubview(headerView)
        addSubview(infoView)
        addSubview(participantsView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public func update(participants: [EnginePeer], context: any AccountContextProtocol, animated: Bool) {
        
    }

}
