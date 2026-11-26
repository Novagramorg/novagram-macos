import Foundation
import Cocoa
import TGUIKit

public func applyAvatarStack(_ peers: [Avatar], current: inout [Avatar], avatars: inout [AvatarContentView], avatarsContainer: View, photoSize: NSSize, animated: Bool, makeControl: (Avatar) -> AvatarContentView) {
    let duration = Double(0.2)
    let timingFunction = CAMediaTimingFunctionName.easeOut
    let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: current, rightList: peers)
    
    
    for removed in removed.reversed() {
        let control = avatars.remove(at: removed)
        let peer = current[removed]
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
        let control = makeControl(inserted.1)
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
    
    current = peers
}
