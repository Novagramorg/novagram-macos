import AppKit
import TGUIKit

typealias PeerId = Int
typealias PeerInputActivity = Int
struct Peer { var right: Bool; var left: Bool }
struct Account { var peerId = 0 }
struct Context { var inlinePacksContext: Int? }
struct CustomTheme { var accentColor: NSColor }
struct ActivityTheme { var foreground: NSColor; var background: NSColor }
struct Theme {
    struct Colors { var accent = NSColor.blue }
    var colors = Colors()
    func activity(key: Int, foregroundColor: NSColor, backgroundColor: NSColor) -> ActivityTheme { ActivityTheme(foreground: foregroundColor, background: backgroundColor) }
}
let theme = Theme()
struct RowItem {
    var highlightVerified = true
    var isLookSavedMessage = false
    var peerId = 1
    var account = Account()
    var context: Context?
    var peer = Peer(right: true, left: true)
    var monoforumPeer: Peer?
    var inputActivity: Int? = 1
    var customTheme: CustomTheme?
}

class CountingControl: Control {
    var moves = 0
    var updates = 0
    var geometryNotifications = 0
    var role = ""
    private let observer = AnimatableContentObserver()
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        moves += 1
        observer.update(for: self, target: self, selector: #selector(geometryChanged), options: [.contentBounds, .documentFrame, .ownFrame])
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observer.update(for: self, target: self, selector: #selector(geometryChanged), options: [.contentBounds, .documentFrame, .ownFrame])
    }
    @objc private func geometryChanged() { geometryNotifications += 1 }
}

final class PremiumStatusControl: CountingControl {
    static func control(_ peer: Peer, account: Account, inlinePacksContext: Int?, left: Bool, isSelected: Bool, cached: PremiumStatusControl?, animated: Bool) -> PremiumStatusControl? {
        guard left ? peer.left : peer.right else { return nil }
        let view = cached ?? PremiumStatusControl(frame: CGRect(x: left ? 20 : 10, y: 10, width: 35, height: 24))
        view.role = left ? "left" : "right"
        view.backgroundColor = left ? .green : (isSelected ? .orange : .red)
        view.updates += 1
        return view
    }
}

final class ChatActivitiesModel {
    let view: View? = CountingControl(frame: CGRect(x: 30, y: 10, width: 40, height: 24))
    func update(with: (PeerId, [(Peer, PeerInputActivity)]), for width: CGFloat, theme: ActivityTheme, layout: (Bool) -> Void) {
        let control = view as! CountingControl
        control.role = "activity"
        control.backgroundColor = theme.foreground
        control.updates += 1
        layout(true)
    }
}

final class TrackingContainer: Control {
    var additions = 0
    override func addSubview(_ view: NSView) {
        additions += 1
        super.addSubview(view)
    }
}

class RowEnvironment: Control {
    let container = TrackingContainer(frame: CGRect(x: 0, y: 0, width: 300, height: 50))
    var statusControl: PremiumStatusControl?
    var leftStatusControl: PremiumStatusControl?
    var activities: ChatActivitiesModel?
    var isRowSelected = false
    var hiddenStatus = true
    var backdorColor: NSColor { .white }
    var fading: [NSView] = []
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(container)
        let avatar = CountingControl(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        avatar.role = "avatar"
        avatar.backgroundColor = .gray
        container.addSubview(avatar)
    }
    required init?(coder: NSCoder) { fatalError() }
    func bind(_ item: RowItem, animated: Bool = false) { fatalError() }
    func performSubviewRemoval(_ view: NSView, animated: Bool) {
        if animated {
            view.alphaValue = 0.4
            fading.append(view)
        } else {
            view.removeFromSuperview()
        }
    }
    func finishRemovals() {
        for view in fading { view.removeFromSuperview() }
        fading.removeAll()
    }
    var roles: [String] { container.subviews.map { ($0 as? CountingControl)?.role ?? "external" } }
    var active: [CountingControl] { [statusControl, leftStatusControl, activities?.view as? CountingControl].compactMap { $0 }.filter { $0.superview === container } }
}
