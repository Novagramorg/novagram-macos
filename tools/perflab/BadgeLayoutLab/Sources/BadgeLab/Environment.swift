import Cocoa
import TGUIKit

struct ReadState { let count: Int; var isMuted = false }
struct LabTheme {
    struct ChatList {
        let badgeTextColor = NSColor.white
        let badgeMutedBackgroundColor = NSColor.gray
        let badgeBackgroundColor = NSColor.blue
        let badgeSelectedTextColor = NSColor.black
        let badgeSelectedBackgroundColor = NSColor.white
    }
    let chatList = ChatList()
}
let theme = LabTheme()
class ItemEnvironment {
    var badgeText: String?
    var badgeNode: BadgeNode?
    var shortBadgeNode: BadgeNode?
    var badgeSelectedNode: BadgeNode?
    var shortBadgeSelectedNode: BadgeNode?
    var isActiveSelected = false
}
final class GateItem {
    var shouldHideContent = false
    var hasLiveItems = false
    var reads = 0
    var badge: BadgeNode?
    var ctxShortBadgeNode: BadgeNode? { reads += 1; return badge }
}
