import Cocoa
import TGUIKit

enum SplitState { case single, dual, minimisize }
final class Context { var layout: SplitState = .dual }
final class Badge {
    let size = NSSize(width: 22, height: 18)
    var aroundFill: NSColor?
    weak var view: View?
    var displays = 0
    func setNeedDisplay() { displays += 1; view?.backgroundColor = .systemRed }
}
final class ChatListRowItem: TableRowItem {
    let context = Context()
    var splitState: SplitState = .dual
    var hideContent = true
    var shouldHideContent: Bool { hideContent || context.layout == .minimisize }
    var getHideProgress: (() -> CGFloat?)?
    var ctxShortBadgeNode: Badge? = Badge()
    var hasLiveItems = false
    var rowClass: AnyClass = CandidateRow.self
    override var height: CGFloat { 70 }
    override func viewClass() -> AnyClass { rowClass }
}
class RowEnvironment: TableRowView {
    let contentView = LayoutTrackingView(frame: NSRect(x: 0, y: 0, width: 280, height: 70))
    let containerView = View(frame: NSRect(x: 0, y: 0, width: 320, height: 70))
    var badgeShortView: View?
    var bindings = 0
    var layoutRequests = 0
    override var needsLayout: Bool {
        get { super.needsLayout }
        set { if newValue { layoutRequests += 1 }; super.needsLayout = newValue }
    }
    var revealActionInvoked = false
    var _backgroundColor: NSColor { .white }
    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(containerView)
        containerView.addSubview(contentView)
        contentView.backgroundColor = .systemBlue
    }
    required init?(coder: NSCoder) { fatalError() }
    override func set(item: TableRowItem, animated: Bool = false) {
        bindings += 1
        super.set(item: item, animated: animated)
    }
    func badgeShortPoint(_ item: ChatListRowItem) -> NSPoint { NSPoint(x: 285, y: 42) }
}

final class LayoutTrackingView: View {
    var layoutRequests = 0
    override var needsLayout: Bool {
        get { super.needsLayout }
        set { if newValue { layoutRequests += 1 }; super.needsLayout = newValue }
    }
}
struct ControllerTarget {
    struct Stake { var keepLeft: CGFloat = 70 }
    var stake = Stake()
}
enum SwipeState {
    case start, swiping(delta: CGFloat), success(delta: CGFloat), failed(delta: CGFloat)
    var delta: CGFloat {
        switch self {
        case .start: return 0
        case let .swiping(delta), let .success(delta), let .failed(delta): return delta
        }
    }
}
final class ControllerView {
    let tableView: TableView
    let backgroundView = View()
    var updates = 0
    init(_ table: TableView) { tableView = table }
    func updateSwipingState(_ state: SwipeState, controller: ControllerTarget) { updates += 1 }
}
class ControllerEnvironment {
    var frame = NSRect(x: 0, y: 0, width: 320, height: 500)
    let genericView: ControllerView
    var swipeState: SwipeState?
    init(_ table: TableView) { genericView = ControllerView(table) }
    func updateSwipingState(_ state: SwipeState, controller: ControllerTarget, isPrevious: Bool) {}
}
