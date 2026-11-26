import Cocoa
import TGUIKit

enum AccessoryType {
    case none
    case switchable(Bool)
    case selectable(Bool)
    case context(String)
    case nextContext(String)
    case contextColored(String, NSColor)
}

struct AccessoryTheme {
    var grayTextColor: NSColor = .gray
    var accentColor: NSColor = .systemBlue
}

struct AccessoryColors {
    var grayText: NSColor = .gray
    var accent: NSColor = .systemBlue
    var background: NSColor = .white
    var underSelectedColor: NSColor = .white
}

struct AccessoryGlobalTheme {
    var colors = AccessoryColors()
    var icons = BadgeIcons()
}

var theme = AccessoryGlobalTheme()

enum AccessoryIcon {
    case iconUsernameAvailability
    case starSmall
}

final class TelegramThemeHooks {
    static let shared = TelegramThemeHooks()
    var source = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12)).fill()
        return true
    }
    var starSource = paidBadgeStarImage()
    func image(_ name: AccessoryIcon) -> NSImage {
        switch name {
        case .iconUsernameAvailability: return source
        case .starSmall: return starSource
        }
    }
}

final class AccessoryItem {
    struct Action {
        let icon: CGImage
        let index: Int
        var accessibilityLabel: String?
    }
    struct Actions {
        var actions: [Action] = []
        var callback: (Int, Int) -> Void = { _, _ in }
    }
    var type: AccessoryType = .none
    var customTheme: AccessoryTheme?
    var statusStyle = ControlStyle(font: .systemFont(ofSize: 13), foregroundColor: .gray)
    var action: () -> Void = {}
    var enabled = true
    var badgeAction: ((NSView) -> Void)?
    var rightActions = Actions()
    var peerId = 1
}

class AccessoryEnvironment: View {
    let containerView = View(frame: NSRect(x: 0, y: 0, width: 400, height: 60))
    var contextLabel: TextView?
    var contextLabelBg: View?
    var choiceControl: ImageView?
    var switchView: SwitchView?
    var rightsActions: [ImageButton] = []

    override convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 400, height: 60))
    }
    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(containerView)
    }
    required init?(coder: NSCoder) { fatalError() }
    func bind(_ item: AccessoryItem, animated: Bool = false) {}
}
