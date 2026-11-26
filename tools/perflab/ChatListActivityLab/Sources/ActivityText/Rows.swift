import AppKit
import TGUIKit

enum PeerListState {
    struct InputActivities {
        struct Activity: Equatable {
            let peer: PeerEquatable
            let activity: PeerInputActivity
            init(_ peer: Peer, _ activity: PeerInputActivity) {
                self.peer = PeerEquatable(peer)
                self.activity = activity
            }
        }
    }
}
final class ChatListRowItem {
    var inputActivityWidth: CGFloat
    var activities: [PeerListState.InputActivities.Activity]
    init(width: CGFloat, activities: [(Peer, PeerInputActivity)]) {
        inputActivityWidth = width
        self.activities = activities.map { .init($0.0, $0.1) }
    }
}
struct TestMessage { let id: Int }
struct LabTheme {
    struct ChatList { var activitySelectedColor = NSColor.red }
    struct Colors { var grayIcon = NSColor.blue; var background = NSColor.white }
    var chatList = ChatList()
    var colors = Colors()
    func activity(key: Int, foregroundColor: NSColor, backgroundColor: NSColor) -> ActivitiesTheme {
        ActivitiesTheme(textColor: foregroundColor, backgroundColor: backgroundColor)
    }
}
var theme = LabTheme()
final class ChatActivitiesModel: MeasuredActivitiesModel {
    var updates = 0
    override func update(with activities: (PeerId, [(Peer, PeerInputActivity)]), for width: CGFloat, theme: ActivitiesTheme, layout: @escaping (Bool) -> Void) {
        updates += 1
        super.update(with: activities, for: width, theme: theme, layout: layout)
    }
}
class RowEnvironment: NSView {
    var item: AnyObject?
    var activitiesModel: ChatActivitiesModel?
    let contentView = View()
    var currentMediaPreviewSpecs: [(TestMessage, Int, Int)] = []
    var mediaPreviewViews: [Int: NSView] = [:]
    var highlighed = false
    var backdorColor: NSColor { .white }
    var onHiddenChange: (() -> Void)?
    var hiddenMessage = false {
        didSet { if oldValue != hiddenMessage { onHiddenChange?() } }
    }
    var textLayout: TextViewLayout? {
        activitiesModel?.view?.subviews.compactMap { $0 as? TextView }.first?.textLayout
    }
}
