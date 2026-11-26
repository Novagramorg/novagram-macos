import Cocoa
import TGUIKit

struct FixturePalette { let grayBackground = NSColor.gray }
struct FixtureChat {
    func chat_reply_swipe_bubble(theme: FixturePresentation) -> CGImage { theme.icons.chat_swipe_reply }
}
struct FixtureIcons {
    var chat_swipe_reply: CGImage { generateImage(NSSize(width: 12, height: 12), contextGenerator: { size, context in
        context.clear(size.bounds)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(size.bounds.insetBy(dx: 3, dy: 3))
    })! }
}
struct FixturePresentation {
    let chatBackground = NSColor.white
    let chatServiceItemColor = NSColor.blue
    let chat = FixtureChat()
    let icons = FixtureIcons()
    let colors = FixturePalette()
}
final class ChatRowItem {
    var isBubbled = true
    let presentation = FixturePresentation()
    var replies = 0
    var onReply: (() -> Void)?
    func replyAction() -> Bool { replies += 1; onReply?(); return true }
}
class RowEnvironment: View {
    let rowView = View()
    var item: AnyObject? = ChatRowItem()
    var haptics = 0
    required init(frame: NSRect) {
        super.init(frame: frame)
        rowView.frame = bounds
        addSubview(rowView)
    }
    required init?(coder: NSCoder) { fatalError() }
    func recordHaptic() { haptics += 1 }
}
