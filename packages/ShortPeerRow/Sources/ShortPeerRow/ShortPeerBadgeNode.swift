import Cocoa
import TGUIKit

public protocol ShortPeerBadgeNode: AnyObject {
    var isSelected: Bool { get set }
    var customLayout: Bool { get set }
    var size: NSSize { get }
    var view: View? { get set }
    var onUpdate: (() -> Void)? { get set }
}
