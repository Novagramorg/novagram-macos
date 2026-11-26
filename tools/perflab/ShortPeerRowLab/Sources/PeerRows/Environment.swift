import Cocoa
import TGUIKit

final class SelectPeerInteraction: InterfaceObserver {
    func emit(_ value: Int) { notifyObservers(value: value, oldValue: 0, animated: false) }
}
enum ShortPeerItemInteractionType {
    case plain
    case selectable(SelectPeerInteraction, Int)
    case interactable(SelectPeerInteraction)
    case deletable
}
enum RowType {
    case none, switchable, selectable
    case context(String), contextColored(String, NSColor), nextContext(String)
}
enum RowViewType {
    case legacy
    case modern(Int, NSEdgeInsets)
}
struct Peer {
    var isScam = false
    var isFake = false
    var isPremium = false
    var isVerified = false
}
struct Action { let icon: CGImage }
struct Actions { var actions: [Action] = [] }
class ItemEnvironment {
    var peerId = 1
    var drawStarsPaid: BadgeAmount?
    var title: (TextNodeLayout, TextNode)?
    var titleSelected: (TextNodeLayout, TextNode)? { nil }
    var status: (TextNodeLayout, TextNode)?
    var statusSelected: (TextNodeLayout, TextNode)? { nil }
    let titleAttr: NSAttributedString?
    let statusAttr: NSAttributedString?
    let statusStyle = ControlStyle(font: .systemFont(ofSize: 13), foregroundColor: .gray)
    var interactionType: ShortPeerItemInteractionType = .plain
    var type: RowType = .none
    var viewType: RowViewType = .legacy
    var badgeNode: Bool?
    var monoforumMessagesSelected: TextViewLayout?
    var customActionText: TextViewLayout?
    var peer = Peer()
    var statusImage: CGImage?
    var rightActions = Actions()
    var highlightVerified = false
    var size = NSSize(width: 320, height: 50)
    var width: CGFloat { size.width }
    var inset = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    var textAdditionInset: CGFloat = 0
    var titleInset: CGFloat = 56
    var statusInset: CGFloat = 56
    func textInset(_ status: Bool) -> CGFloat { status ? statusInset : titleInset }
    init(title: String? = "A name with 🦆 and a long surname", status: String? = "last seen recently", color: NSColor = .black, font: NSFont = .systemFont(ofSize: 14)) {
        titleAttr = title.map { NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: color, .selectedColor: NSColor.white]) }
        statusAttr = status.map { NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.gray, .selectedColor: NSColor.white]) }
    }
    var layouts: [(TextNodeLayout, TextNode)?] { [title, titleSelected, status, statusSelected] }
}

private let labImages = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    image.setName(name)
    return image
}
func initializeLab() {
    _ = NSApplication.shared
    _ = labImages
    System.updateScaleFactor(2)
}
