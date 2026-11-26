import AppKit
import ScrollTypes

final class TableRowItem {
    let stableId: Int
    let height: CGFloat
    let ignoreAtInitialization: Bool
    let text: String
    init(_ id: Int, height: CGFloat, ignored: Bool = false, text: String = "") {
        self.stableId = id
        self.height = height
        self.ignoreAtInitialization = ignored
        self.text = text
    }
}

struct HistoryView {
    let filteredEntries: [TableRowItem]
}

enum TableSavingSide { case upper }
enum TableScrollState {
    case top(id: AnyHashable, innerId: AnyHashable?, animated: Bool, focus: TableScrollFocus, inset: CGFloat)
    case center(id: AnyHashable, innerId: AnyHashable?, animated: Bool, focus: TableScrollFocus, inset: CGFloat)
    case saveVisible(TableSavingSide, Bool)
}

struct Selection {
    let start: Int
    let insertions: [(Int, TableRowItem)]
    var rows: [TableRowItem] { insertions.map { $0.1 } }
    var ids: [Int] { rows.map { $0.stableId } }
}

struct TableUpdateTransition {
    let deleted: [Int]
    let inserted: [(Int, TableRowItem)]
    let updated: [(Int, TableRowItem)]
    let state: TableScrollState
}

final class Subscriber {
    var transitions: [TableUpdateTransition] = []
    var completions = 0
    func putNext(_ value: TableUpdateTransition) { transitions.append(value) }
    func putCompletion() { completions += 1 }
}

final class Cancellation {
    var checks = 0
    let cancelAt: Int
    init(cancelAt: Int = Int.max) { self.cancelAt = cancelAt }
    func with<T>(_ body: (Bool) -> T) -> T {
        checks += 1
        return body(checks >= cancelAt)
    }
}

final class ImmediateQueue {
    func async(_ body: () -> Void) { body() }
}

extension NSRange {
    func indexIn(_ index: Int) -> Bool { index >= location && index - location < length }
}

final class ChatHistoryState {
    let isDownOfHistory: Bool
    init(isDownOfHistory: Bool = true) { self.isDownOfHistory = isDownOfHistory }
}

final class ScrollTable {
    var documentOffset: CGPoint = .zero
    var isEmpty = false
}

class ScrollerButton: NSView {
    var opacityChanges = 0
    var completions: [(Bool) -> Void] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func change(opacity: CGFloat, animated: Bool, completion: @escaping (Bool) -> Void) {
        opacityChanges += 1
        if layer!.opacity == Float(opacity) {
            completion(true)
        } else {
            layer!.opacity = Float(opacity)
            if animated {
                completions.append(completion)
            } else {
                completion(true)
            }
        }
    }
}

enum TransitionCurve { case easeOut }
enum ContainedViewLayoutTransition {
    case immediate
    case animated(duration: Double, curve: TransitionCurve)
    var isAnimated: Bool {
        if case .animated = self { return true }
        return false
    }
    func updateFrame(view: ScrollerButton, frame: NSRect) {
        (view.superview as? ScrollerFixture)?.frameUpdates += 1
        if view.frame != frame { view.frame = frame }
    }
}

final class InputFixture {
    var anchors: [CGPoint?] = []
    func updateFloatingColumnAnchor(_ anchor: CGPoint?, transition: ContainedViewLayoutTransition) {
        anchors.append(anchor)
    }
}

class ScrollerFixture: NSView {
    var historyState: ChatHistoryState?
    var scrollerTargetIsHidden: Bool?
    let tableView = ScrollTable()
    let scroller = ScrollerButton(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    var mentions: ScrollerButton? = ScrollerButton(frame: .zero)
    var reactions: ScrollerButton? = ScrollerButton(frame: .zero)
    var pollVotes: ScrollerButton? = ScrollerButton(frame: .zero)
    let inputView = InputFixture()
    var frameUpdates = 0
    var scrollerRect: NSRect { NSRect(x: frame.width - 50, y: frame.height - 100, width: 50, height: 50) }
    var mentionsRect: NSRect { scrollerRect.offsetBy(dx: 0, dy: -50) }
    var reactionsRect: NSRect { scrollerRect.offsetBy(dx: 0, dy: -100) }
    var pollVotesRect: NSRect { scrollerRect.offsetBy(dx: 0, dy: -150) }
    var floatingColumnAnchor: CGPoint? { convert(pollVotesRect.origin, to: nil) }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 720))
        [scroller, mentions, reactions, pollVotes].compactMap { $0 }.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class RevealView: NSView {
    var hasRevealState: Bool = false
}

final class RevealItem {
    let rowView: NSView?
    var lookups = 0
    init(_ rowView: NSView?) { self.rowView = rowView }
    var view: NSView? {
        lookups += 1
        return rowView
    }
}

func center(_ id: Int, inset: CGFloat = 0, innerId: Int? = nil, string: String? = nil) -> TableScrollState {
    .center(id: id, innerId: innerId.map(AnyHashable.init), animated: false, focus: TableScrollFocus(focus: false, string: string), inset: inset)
}
