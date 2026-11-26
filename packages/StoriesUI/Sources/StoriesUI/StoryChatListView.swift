import Foundation
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import ObjcUtils
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramIconsTheme
import Localization
import LocalAnimations
import AvatarUI
import ColorPalette
import FoundationUtils
import InAppSettings


private struct StoryChatListEntry : Equatable, Comparable, Identifiable {
    
    public struct Name : Equatable {
        let text: String
        let color: NSColor
    }
    
    public let item: EngineStorySubscriptions.Item
    public let name: Name
    public let index: Int
    public let appearance: TelegramPresentationTheme
    
    public static func <(lhs: StoryChatListEntry, rhs: StoryChatListEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    public static func ==(lhs: StoryChatListEntry, rhs: StoryChatListEntry) -> Bool {
        if lhs.item != rhs.item {
            return false
        }
        if lhs.name != rhs.name {
            return false
        }
        return lhs.appearance == rhs.appearance
    }
    
    public var stableId: AnyHashable {
        return item.peer.id
    }
    public var id: PeerId {
        return item.peer.id
    }
    public var hasUnseen: Bool {
        return self.item.hasUnseen
    }
}



public final class StoryListChatListRowItem : TableRowItem {
    
    public enum InterfaceState : Equatable {
        
        public enum From {
            case concealed
            case revealed
        }
        
        case revealed
        case concealed
        case empty
        case progress(CGFloat, From, Bool)
        
        public var height: CGFloat {
            switch self {
            case .revealed:
                return 66
            case .concealed:
                return 30
            case .empty:
                return 0
            case let .progress(progress, _, _):
                return 30 + 36 * progress
            }
        }
        
        public var toHideProgress: Bool {
            switch self {
            case let .progress(_, from, _):
                return from == .revealed
            default:
                return false
            }
        }
        public var toRevealProgress: Bool {
            switch self {
            case let .progress(_, from, _):
                return from == .concealed
            default:
                return false
            }
        }
        
        public var initFromEvent: Bool? {
            switch self {
            case let .progress(_, _, initFromEvent):
                return initFromEvent
            default:
                return nil
            }
        }
        
        public var navigationHeight: CGFloat {
            return InterfaceState.revealed.height * self.progress + (9 * self.progress)
        }
        public var progress: CGFloat {
            switch self {
            case .revealed:
                return 1.0
            case .concealed:
                return 0.0
            case .empty:
                return 0.0
            case let .progress(progress, _, _):
                return progress
            }
        }
        
        public var isProgress: Bool {
            switch self {
            case .progress:
                return true
            default:
                return false
            }
        }
        
        public static var small: CGFloat {
            return 30
        }
        public static var full: CGFloat {
            return 66
        }
    }
    
    private let _stableId: AnyHashable
    public let context: any AccountContextProtocol
    public let state: EngineStorySubscriptions
    public let isArchive: Bool
    public let open: (StoryInitialIndex?, Bool, Bool)->Void
    public let getInterfaceState: ()->InterfaceState
    public let reveal: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, isArchive: Bool, state: EngineStorySubscriptions, open:@escaping(StoryInitialIndex?, Bool, Bool)->Void, getInterfaceState: @escaping()->InterfaceState = { return .revealed }, reveal: @escaping()->Void) {
        self._stableId = stableId
        self.context = context
        self.isArchive = isArchive
        self.state = state
        self.open = open
        self.reveal = reveal
        self.getInterfaceState = getInterfaceState
        super.init(initialSize)
    }
    
    
    public var itemsCount: Int {
        var count: Int = 0
        if !self.isArchive, let accountItem = self.state.accountItem, accountItem.storyCount > 0 {
            count += 1
        }
        count += self.state.items.count
        return count
    }
    
    public static var smallSize: NSSize {
        return NSMakeSize(24, 24)
    }
    public static var fullSize: NSSize {
        return NSMakeSize(44, 44)
    }
    
    public override var stableId: AnyHashable {
        return _stableId
    }
    
    public override var height: CGFloat {
        return getInterfaceState().height
    }
    
    public var progress: CGFloat {
        return getInterfaceState().progress
    }
    
    public var navigationHeight: CGFloat {
        return getInterfaceState().navigationHeight
    }
    
    public override func viewClass() -> AnyClass {
        return StoryListChatListRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonStories
    }
    
    public override var animatable: Bool {
        return true
    }
}

private final class StoryListContainer : Control {
    
    public var loadMore:((ScrollDirection)->Void)? = nil
    
    private var views: [ItemView] = []
    private let documentView = View()
    private let componentsView = View()
    private var components:[ComponentView] = []

    private let scrollView: ScrollView = {
        let view = ScrollView(frame: .zero)
        view.hasVerticalScroller = false
        view.verticalScrollElasticity = .none
        return view
    }()
    private var progress: CGFloat = 1.0

    private var lastAppliedLayout: (size: NSSize, progress: CGFloat, offset: NSPoint)?

    private var documentOffset: NSPoint? = nil
    private var boundsObserver: NSObjectProtocol? = nil

    private var item: StoryListChatListRowItem?

    var forwardVerticalScroll: ((NSEvent) -> Void)?
    private var router = StoryStripScrollRouter()
    private var expandedOffset: CGFloat = 0
    private var applyingOffset = false

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.documentView = documentView
        addSubview(scrollView)
        scrollView.applyExternalScroll = { [weak self] event in
            return self?.route(event) ?? false
        }
        
        self.layer?.masksToBounds = false
        
        
        documentView.layer?.masksToBounds = false
        componentsView.layer?.masksToBounds = false
        self.layer?.masksToBounds = false
        scrollView.layer?.masksToBounds = false
        scrollView.contentView.layer?.masksToBounds = false
        documentView.addSubview(componentsView)
        scrollView.background = .clear
        
        set(handler: { [weak self] _ in
            if self?.superview?.layer?.opacity == 1 {
                self?.item?.reveal()
            }
        }, for: .Click)
        
        boundsObserver = NotificationCenter.default.addObserver(forName: NSScrollView.boundsDidChangeNotification, object: scrollView.clipView, queue: nil, using: { [weak self] _ in
            guard let self else {
                return
            }
            let current = NSMakePoint(floor(abs(self.scrollView.documentOffset.x)), floor(abs(self.scrollView.documentOffset.y)))
                        
            if current != self.documentOffset {
                self.documentOffset = current
                if !self.applyingOffset {
                    self.updateScroll()
                }
            }
        })
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var scrollOffset: NSPoint = .zero

    private func route(_ event: NSEvent) -> Bool {
        guard let forward = self.forwardVerticalScroll else {
            return false
        }
        switch self.router.route(phase: event.phase, momentumPhase: event.momentumPhase, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, expanded: self.progress >= 1, time: event.timestamp) {
        case .forward:
            forward(event)
            return true
        case .ignore:
            return true
        case .native:
            return false
        case let .scrollHorizontally(delta):
            let limit = self.documentView.frame.width - self.scrollView.frame.width
            if let x = StoryStripScrollRouter.wheelOffset(current: self.scrollView.documentOffset.x, delta: delta, limit: limit) {
                self.setHorizontalOffset(floorToScreenPixels(backingScaleFactor, x))
            } else {
                forward(event)
            }
            return true
        }
    }
    
    private var previousVisibleRange: NSRange? = nil
    private func updateScroll() {
        let previous = self.scrollOffset
        let current = scrollView.documentOffset
        self.scrollOffset = current
        
        if previous.x < current.x, (current.x - frame.width) - documentSize.width < frame.width {
            self.loadMore?(.bottom)
        }
        
        if self.progress == 1 {
            self.expandedOffset = current.x
        }
        let visibleRange = self.visibleRange
        if previousVisibleRange != visibleRange, previousVisibleRange != nil, progress == 1 {
            drawVisibleViews()
            self.previousVisibleRange = visibleRange
        } else {
            self.previousVisibleRange = visibleRange
        }
    }
    
    public func drawVisibleViews() {

        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private func getAlpha(_ item: StoryListEntryRowItem, index i: Int, progress: CGFloat) -> CGFloat {
        if visibleRange.contains(i) {
            if !focusRange.contains(i) {
                return progress
            } else {
                return 1.0
            }
        } else {
            return progress == 1.0 ? 1 : 0
        }
    }
    
    private func getFrame(_ item: StoryListEntryRowItem, index i: Int, progress: CGFloat) -> NSRect {
        
        
        let focusRange = self.focusRange
        
        let w = StoryListChatListRowItem.smallSize.width
        let itemSize = NSMakeSize(w + (item.itemWidth - w) * progress, w + (item.itemHeight - w) * progress)
        
        
        let cgCount = CGFloat(views.count)
        let gapBetween = max(10.0, (frame.width - item.itemWidth * cgCount) / (cgCount + 1))

        
        var frame = CGRect(origin: .zero, size: itemSize)
        if i < focusRange.location {
            let w = itemSize.width - (itemSize.width / 2 * (1 - progress))
            let h = itemSize.height - (itemSize.height / 2 * (1 - progress))
            frame.size = NSMakeSize(w, h)
            
            frame.origin.x = (CGFloat(i) * itemSize.width)

            frame.origin.x += (gapBetween + (CGFloat(i) * gapBetween))
        } else {
            
            if i >= focusRange.max {
                let w = itemSize.width - (itemSize.width / 2 * (1 - progress))
                let h = itemSize.height - (itemSize.height / 2 * (1 - progress))
                frame.size = NSMakeSize(w, h)
            }
            
            frame.origin.x = ((1.0 - progress) * CGFloat(i - focusRange.location)) * itemSize.width + (CGFloat(i) * itemSize.width * progress) + ((1.0 - progress) * 13.0)
            
            let insets = (gapBetween + (CGFloat(i) * gapBetween)) * progress
            frame.origin.x += insets
            
            if i > focusRange.max {
                frame.origin.x -= gapBetween * CGFloat(i - focusRange.max) * (1 - progress)
            }
            if i > focusRange.location {
                frame.origin.x -= ((1.0 - progress) * itemSize.width / 2) * CGFloat(i - focusRange.location)
            }
        }
        frame.origin.y = (self.frame.height - frame.height) / 2
        
        
        return frame.toScreenPixel
    }
    
    
    public func set(transition: TableUpdateTransition, item: StoryListChatListRowItem, context: any AccountContextProtocol, progress: CGFloat, animated: Bool) {

        self.progress = progress
        self.item = item
        
        if !transition.isEmpty {
            var toRemove_v:[AnyHashable : ItemView] = [:]
            var toRemove_c:[AnyHashable : ComponentView] = [:]

            for deleted in transition.deleted.reversed() {
                let view = views.remove(at: deleted)
                let component = components.remove(at: deleted)
                if let item = view.item {
                    toRemove_v[item.stableId] = view
                } else {
                    performSubviewRemoval(view, animated: animated, scale: true)
                }
                if let item = component.item {
                    toRemove_c[item.stableId] = component
                } else {
                    performSubviewRemoval(view, animated: animated, scale: true)
                }
            }
            for inserted in transition.inserted {
                let item = inserted.1 as! StoryListEntryRowItem
                
                let view: ItemView
                let component: ComponentView
                let isNew: Bool
                if let v = toRemove_v[item.stableId] {
                    let c = toRemove_c[item.stableId]!
                    views.insert(v, at: inserted.0)
                    components.insert(c, at: inserted.0)
                    toRemove_v.removeValue(forKey: item.stableId)
                    toRemove_c.removeValue(forKey: item.stableId)
                    view = v
                    component = c
                    isNew = false
                } else {
                    let rect = getFrame(item, index: inserted.0, progress: progress)
                    let alpha = Float(getAlpha(item, index: inserted.0, progress: progress))
                    view = ItemView(frame: rect)
                    component = ComponentView(frame: rect)
                    
                    views.insert(view, at: inserted.0)
                    components.insert(component, at: inserted.0)
                    
                    view.layer?.opacity = alpha
                    component.layer?.opacity = alpha
                    
                    isNew = true
                }
                
                view.set(item: item, open: { [weak self] item in
                    self?.open(item)
                }, progress: progress, animated: false)
                
                component.set(item: item, open: { [weak self] item in
                    self?.open(item)
                }, progress: progress, animated: false)
                
                if inserted.0 == 0 {
                    documentView.addSubview(view, positioned: .above, relativeTo: componentsView)
                } else {
                    documentView.addSubview(view, positioned: .above, relativeTo: views[inserted.0 - 1])
                }
                
                if inserted.0 == 0 {
                    componentsView.addSubview(component, positioned: .below, relativeTo: componentsView.subviews.first)
                } else {
                    componentsView.addSubview(component, positioned: .above, relativeTo: components[inserted.0 - 1])
                }
                
                
                if animated, isNew {
                    view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    view.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                    
                    component.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    component.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)

                }
            }
            for updated in transition.updated {
                views[updated.0].set(item: updated.1, open: { [weak self] item in
                    self?.open(item)
                }, progress: progress, animated: animated)
                
                components[updated.0].set(item: updated.1, open: { [weak self] item in
                    self?.open(item)
                }, progress: progress, animated: animated)
            }
            
            for (_, view) in toRemove_c {
                performSubviewRemoval(view, animated: animated, scale: true)
            }
            for (_, view) in toRemove_v {
                performSubviewRemoval(view, animated: animated, scale: true)
            }
            toRemove_c.removeAll()
            toRemove_v.removeAll()
        }
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate

        self.applyCollapseOffset()
        self.updateLayout(size: frame.size, transition: transition)

        
        for (i, view) in views.enumerated() {
            view.component = components[i]
            
            if focusRange.contains(i) {
                view.layer?.zPosition = 1000.0 - CGFloat(i)
            } else {
                view.layer?.zPosition = CGFloat(views.count - i)
            }
            view.userInteractionEnabled = progress == 1.0
        }
        for (i, view) in components.enumerated() {
            view.layer?.zPosition = CGFloat(i)
        }
        self.userInteractionEnabled = progress != 1.0
    }
    
    #if DEBUG
    var debugHorizontalOffset: CGFloat {
        return self.scrollView.contentView.layer?.presentation()?.bounds.origin.x ?? self.scrollView.documentOffset.x
    }

    func debugResetHorizontalOffset() {
        self.expandedOffset = 0
        self.setHorizontalOffset(0)
    }
    #endif

    private func applyCollapseOffset() {
        let target: CGFloat
        if progress >= 1 {
            target = self.expandedOffset
        } else {
            if progress <= 0 {
                self.expandedOffset = 0
            }
            target = floorToScreenPixels(backingScaleFactor, self.expandedOffset * progress)
        }
        if abs(self.scrollView.documentOffset.x - target) >= 0.5 {
            self.applyingOffset = true
            self.setHorizontalOffset(target)
            self.applyingOffset = false
            self.scrollOffset = self.scrollView.documentOffset
        }
    }

    private func setHorizontalOffset(_ x: CGFloat) {
        self.scrollView.clipView.scroll(to: NSMakePoint(x, 0))
        self.scrollView.reflectScrolledClipView(self.scrollView.clipView)
    }

    public var focusRange: NSRange {
        let count = self.item?.itemsCount ?? views.count
        if let itemView = views.first, itemView.item?.peerId == item?.context.peerId {
            if count > 3 {
                return NSMakeRange(1, 3)
            } else {
                if views.count > 3, views[1].item?.entry.hasUnseen == true {
                    return NSMakeRange(1, min(3, count))
                } else {
                    return NSMakeRange(0, min(3, count))
                }
            }
        } else {
            return NSMakeRange(0, min(3, count))
        }
    }
    
    public var visibleRange: NSRange {
        
        let visibleRect = scrollView.documentVisibleRect
        
        var range: NSRange = NSMakeRange(NSNotFound, 0)
        for (i, view) in views.enumerated() {
            if let item = view.item {
                let frame = getFrame(item, index: i, progress: 1)
                if range.location == NSNotFound {
                    if visibleRect.intersects(frame) {
                        range.location = i
                        range.length += 1
                    }
                } else {
                    if visibleRect.intersects(frame) {
                        range.length += 1
                    } else {
                        break
                    }
                }
            }
           
        }

        if range.location == NSNotFound {
            range.location = 0
            range.length = views.count
        } else {
            let lower = max(0, range.location - 1)
            let upper = min(views.count, range.location + range.length + 1)
            range = NSMakeRange(lower, upper - lower)
        }
        
        return range
    }
    
    public var documentSize: NSSize {
        if views.count > 0, let view = views.last, let item = view.item {
            let index = views.count - 1
            return NSMakeSize(max(frame.width, getFrame(item, index: index, progress: progress).maxX + 10), frame.height)
        } else {
            return frame.size
        }
    }
    
    
    public var unitDocumentSize: NSSize {
        let count = CGFloat(views.count)
        return NSMakeSize(10 + (count * 50) + ((count - 1) * 20) + 10, frame.height)
    }
    
    private func open(_ item: StoryListEntryRowItem) {
        let peerId = item.entry.id
        item.open(.init(peerId: peerId, id: nil, messageId: nil, takeControl: { [weak self] peerId, _, _ in
            return self?.scrollAndFindItem(peerId, animated: false)
        }, setProgress: { [weak self] value in
            self?.setProgress(peerId, value)
        }), false, self.item?.isArchive ?? false)
    }
    
    public func setProgress(_ peerId: PeerId, _ value: Signal<Never, NoError>) {
        if let view = findItemView(peerId) {
            view.setOpenProgress(value)
        }
    }
    
    private func findItemView(_ peerId: PeerId) -> ItemView? {
        for view in views {
            if view.item?.entry.id == peerId {
                return view
            }
        }
        return nil
    }
    
    private func scrollAndFindItem(_ peerId: PeerId, animated: Bool) -> NSView? {
        for (index, view) in views.enumerated() {
            if view.item?.entry.id == peerId {
                if self.progress >= 1, !self.scrollView.documentVisibleRect.contains(view.frame) {
                    self.scroll(index: index, animated: animated, toVisible: false)
                    self.drawVisibleViews()
                }
                return view.isHidden ? nil : view.imageView
            }
        }
        return nil
    }
    
    private func scroll(index: Int, animated: Bool, toVisible: Bool) {
        let view = self.views[index]
        if toVisible && view.visibleRect.width < view.frame.width / 2 || !toVisible {
            let x = min(max(view.frame.midX - frame.width / 2, 0), max(documentView.frame.width - frame.width, 0))
            if animated {
                scrollView.clipView.scroll(to: NSMakePoint(x, 0), animated: true)
            } else {
                self.setHorizontalOffset(x)
            }
        }
    }
    
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {

        let offset = scrollView.documentOffset
        if let last = lastAppliedLayout, last.size == size, last.progress == progress, last.offset == offset {
            return
        }
        lastAppliedLayout = (size, progress, offset)

        let documentRect = CGRect(origin: .zero, size: documentSize)
        transition.updateFrame(view: documentView, frame: documentRect)
        transition.updateFrame(view: componentsView, frame: documentRect)

        scrollView.contentView._change(size: CGSize(width: scrollView.contentView.bounds.width, height: size.height), animated: transition.isAnimated, duration: transition.duration, timingFunction: transition.timingFunction)
        

        transition.updateFrame(view: scrollView, frame: size.bounds)
                
        let visibleRange = self.visibleRange
        for (i, view) in views.enumerated() {
            if let item = view.item {
                let component = components[i]

                
                let frame = getFrame(item, index: i, progress: progress)
                let alpha = getAlpha(item, index: i, progress: progress)
                

                view.isHidden = !visibleRange.contains(i)
                component.isHidden = !visibleRange.contains(i)

                if !view.isHidden {
                    transition.updateFrame(view: view, frame: frame)
                    transition.updateAlpha(view: view, alpha: alpha)
                    view.set(progress: progress, transition: transition)
                }
                if !component.isHidden  {
                    transition.updateFrame(view: component, frame: frame)
                    transition.updateAlpha(view: component, alpha: alpha)
                    component.set(progress: progress, transition: transition)
                }
            }
        }
        
    }
}

public enum StoryRevealAxis {
    case horizontal
    case vertical
}

public final class StoryListChatListRowView: TableRowView {
        
    private let interfaceView: StoryListContainer

    #if DEBUG
    public var debugHorizontalOffset: CGFloat {
        return self.interfaceView.debugHorizontalOffset
    }

    public func debugResetHorizontalOffset() {
        self.interfaceView.debugResetHorizontalOffset()
    }
    #endif

    public var forwardVerticalScroll: ((NSEvent) -> Void)? {
        get {
            return self.interfaceView.forwardVerticalScroll
        }
        set {
            self.interfaceView.forwardVerticalScroll = newValue
        }
    }

    private var lastState: EngineStorySubscriptions?
    private var lastIsArchive: Bool?
    private weak var lastTheme: TelegramPresentationTheme?
    private var lastMyStoryTitle: String?
    
    
    public required init(frame frameRect: NSRect) {
        self.interfaceView = StoryListContainer(frame: NSMakeRect(0, 0, max(frameRect.width, 300), frameRect.height))
        super.init(frame: frameRect)
        addSubview(interfaceView)
        
        self.layer?.masksToBounds = false
        

        interfaceView.loadMore = { [weak self] direction in
            switch direction {
            case .bottom:
                if let item = self?.item as? StoryListChatListRowItem {
                    if let _ = item.state.hasMoreToken {
                        item.context.account.filteredStorySubscriptionsContext?.loadMore()
                    }
                }
            default:
                break
            }
        }
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }


    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var current: [StoryChatListEntry] = []
    
    private var interfaceState: StoryListChatListRowItem.InterfaceState?
    public override func set(item: TableRowItem, animated: Bool = false) {
        
        super.set(item: item, animated: animated)
        
        guard let item = item as? StoryListChatListRowItem else {
            return
        }

        let myStoryTitle = strings().storyListMyStory
        if let lastState = self.lastState, lastState == item.state, self.lastIsArchive == item.isArchive, self.lastTheme === theme, self.lastMyStoryTitle == myStoryTitle {
            self.interfaceState = item.getInterfaceState()
            self.interfaceView.set(transition: TableUpdateTransition(deleted: [], inserted: [], updated: [], animated: false, grouping: false, animateVisibleOnly: false), item: item, context: item.context, progress: item.progress, animated: animated)
            return
        }
        self.lastState = item.state
        self.lastIsArchive = item.isArchive
        self.lastTheme = theme
        self.lastMyStoryTitle = myStoryTitle
        
        var entries:[StoryChatListEntry] = []
        var index: Int = 0
        if !item.isArchive, let item = item.state.accountItem, item.storyCount > 0 {
            let name: StoryChatListEntry.Name = .init(text: myStoryTitle, color: theme.colors.text)
            entries.append(.init(item: item, name: name, index: index, appearance: theme))
            index += 1
        }
        
        for item in item.state.items {
            if item.storyCount > 0 {
                let name: StoryChatListEntry.Name = .init(text: item.peer._asPeer().compactDisplayTitle, color: item.hasUnseen ? theme.colors.text : theme.colors.grayText)
                entries.append(.init(item: item, name: name, index: index, appearance: theme))
                index += 1
            }
        }
        

        
        _ = self.interfaceState
        let interfaceState = item.getInterfaceState()
        self.interfaceState = interfaceState
        
                
      

        let initialSize = NSMakeSize(item.height, item.height)
        let context = item.context

        let (deleted, inserted, updated) = proccessEntriesWithoutReverse(self.current, right: entries, { entry in
            return StoryListEntryRowItem(initialSize, entry: entry, context: context, open: item.open)
        })
        let transition = TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: animated, grouping: false, animateVisibleOnly: false)

        self.interfaceView.set(transition: transition, item: item, context: item.context, progress: item.progress, animated: animated)
        

        self.current = entries
        
        if interfaceView.unitDocumentSize.width < interfaceView.frame.width * 10 {
            if let _ = item.state.hasMoreToken {
                item.context.account.filteredStorySubscriptionsContext?.loadMore()
            }
        }
        
    }
    
    
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        let rect = NSMakeSize(max(300, size.width), size.height).bounds
        transition.updateFrame(view: interfaceView, frame: rect)
        interfaceView.updateLayout(size: rect.size, transition: transition)
    }
}

private final class StoryListEntryRowItem : TableRowItem {
    public let entry: StoryChatListEntry
    public let context: any AccountContextProtocol
    
    public let stateComponent: AvatarStoryIndicatorComponent

    public let open:(StoryInitialIndex?, Bool, Bool)->Void
    public init(_ initialSize: NSSize, entry: StoryChatListEntry, context: any AccountContextProtocol, open: @escaping(StoryInitialIndex?, Bool, Bool)->Void) {
        self.entry = entry
        self.context = context
        self.open = open
        self.stateComponent = .init(story: entry.item, presentation: presentation, isRoundedRect: false)
        super.init(initialSize)
    }
    
    public var peerId: PeerId {
        return entry.item.peer.id
    }
    
    public override var stableId: AnyHashable {
        return entry.stableId
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items: [ContextMenuItem] = []
        let peerId = self.entry.item.peer.id
        let context = self.context
        
        let addStealthMode:()->Void = {
            items.append(.init(strings().storyControlsMenuStealtMode, handler: {
                let stealthData = context.engine.data.subscribe(
                    TelegramEngine.EngineData.Item.Configuration.StoryConfigurationState()
                ) |> deliverOnMainQueue |> take(1)
                
                _ = stealthData.start(next: { value in
                    if let timestamp = value.stealthModeState.activeUntilTimestamp {
                        showModalText(for: context.window, text: strings().storyTooltipStealthModeActive(smartTimeleftText(Int(timestamp - context.timestamp))))
                    } else {
                        showModal(with: StoryStealthModeController(context, enableStealth: {
                            _ = context.engine.messages.enableStoryStealthMode().start()
                            let stealthData = context.engine.data.subscribe(
                                TelegramEngine.EngineData.Item.Configuration.StoryConfigurationState()
                            ) |> deliverOnMainQueue |> take(1)
                            
                            _ = stealthData.start(next: { value in
                                if let timestamp = value.stealthModeState.activeUntilTimestamp {
                                     showModalText(for: context.window, text: strings().storyTooltipStealthModeActive(smartTimeleftText(Int(timestamp - context.timestamp))))
                                }
                            })
                        }, presentation: theme), for: context.window)
                    }
                })
            }, itemImage: MenuAnimation.menu_eye_slash.value))
        }
        
        if context.peerId != peerId {
            if !self.entry.item.peer.isService {
                let isChannel = self.entry.item.peer._asPeer().isChannel
                let title = isChannel ? strings().storyListContextOpenChannel : strings().storyListContextSendMessage
                
                items.append(.init(title, handler: {
                    StoriesHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(peerId))
                }, itemImage: isChannel ? MenuAnimation.menu_channel.value : MenuAnimation.menu_read.value))
                
                if !isChannel {
                    items.append(.init(strings().storyListContextViewProfile, handler: {
                        StoriesHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peerId)
                    }, itemImage: self.entry.item.peer._asPeer().isSupergroup ? MenuAnimation.menu_create_group.value : MenuAnimation.menu_open_profile.value))
                }
                
                
                addStealthMode()
               
                
                let peer = self.entry.item.peer._asPeer()
                if peer.storyArchived {
                    items.append(.init(strings().storyListContextUnarchive, handler: {
                        context.engine.peers.updatePeerStoriesHidden(id: peerId, isHidden: false)
                        showModalText(for: context.window, text: strings().storyListTooltipUnarchive(peer.compactDisplayTitle))
                    }, itemImage: MenuAnimation.menu_unarchive.value))
                } else {
                    items.append(.init(strings().storyListContextArchive, handler: {
                        context.engine.peers.updatePeerStoriesHidden(id: peerId, isHidden: true)
                        showModalText(for: context.window, text: strings().storyListTooltipArchive(peer.compactDisplayTitle))
                    }, itemImage: MenuAnimation.menu_archive.value))
                }
            }
        } else {
            items.append(.init(strings().storyListContextSavedStories, handler: {
                StoriesHooks.shared.pushStoryMedia(context, context.peerId, PeerStoryListContext(account: context.account, peerId: context.peerId, isArchived: false, folderId: nil), true, false)
            }, itemImage: MenuAnimation.menu_stories.value))
            
            items.append(.init(strings().storyListContextArchivedStories, handler: {
                StoriesHooks.shared.pushStoryMedia(context, context.peerId, PeerStoryListContext(account: context.account, peerId: context.peerId, isArchived: true, folderId: nil), true, true)
            }, itemImage: MenuAnimation.menu_archive.value))
            
            addStealthMode()
        }
        

        return .single(items)
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override var height: CGFloat {
        return 70
    }

    public override var width: CGFloat {
        return 86
    }
    
    public var itemHeight: CGFloat {
        return 66
    }
    public var itemWidth: CGFloat {
        return 50
    }

    public override var accessibilityLabel: String? {
        return entry.name.text + ", " + strings().voiceOverCommonStory
    }

    public override var accessibilityValue: String? {
        return entry.hasUnseen ? strings().voiceOverCommonUnread : nil
    }
}

private final class ComponentView : Control {
    private let stateView = AvatarStoryIndicatorComponent.IndicatorView(frame: StoryListChatListRowItem.fullSize.bounds)
    
    private var loadingStatuses = Bag<Disposable>()

    fileprivate var item: StoryListEntryRowItem?
    private var progress: CGFloat = 1.0
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(stateView)
        stateView.isEventLess = true
        self.userInteractionEnabled = false
        self.isAccessibilityDecorative = true
        self.scaleOnClick = true
        self.layer?.masksToBounds = false

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public func set(item: TableRowItem, open: @escaping(StoryListEntryRowItem)->Void, progress: CGFloat, animated: Bool) {
        guard let item = item as? StoryListEntryRowItem else {
            return
        }
        self.progress = progress
        self.item = item
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        self.updateLayout(size: frame.size, transition: transition)
        
        if progress != 1 {
            self.cancelLoading()
        }
    }
    
    public func set(progress: CGFloat, transition: ContainedViewLayoutTransition) {
        self.progress = progress
        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        guard let item = self.item else {
            return
        }
        
        let stateSize = NSMakeSize(size.width - 6, size.width - 6)
        let stateRect = CGRect(origin: CGPoint(x: (size.width - stateSize.width) / 2, y: 3), size: stateSize)
                
        transition.updateFrame(view: stateView, frame: stateRect.insetBy(dx: -3, dy: -3))
        stateView.update(component: item.stateComponent, availableSize: NSMakeSize(size.width - 6, size.width - 6), progress: progress, transition: transition, displayProgress: !self.loadingStatuses.isEmpty)
        
    }
    

    
    public func cancelLoading() {
        for disposable in self.loadingStatuses.copyItems() {
            disposable.dispose()
        }
        self.loadingStatuses.removeAll()
        self.updateStoryIndicator(transition: .animated(duration: 0.2, curve: .easeOut))
    }
    
    public func pushLoadingStatus(signal: Signal<Never, NoError>) -> Disposable {
        let disposable = MetaDisposable()
        
        let loadingStatuses = self.loadingStatuses
        
        for d in loadingStatuses.copyItems() {
            d.dispose()
        }
        loadingStatuses.removeAll()
        
        let index = loadingStatuses.add(disposable)
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2, execute: { [weak self] in
            self?.updateStoryIndicator(transition: .animated(duration: 0.2, curve: .easeOut))
        })
        
        disposable.set(signal.start(completed: { [weak self] in
            Queue.mainQueue().async {
                loadingStatuses.remove(index)
                if loadingStatuses.isEmpty {
                    self?.updateStoryIndicator(transition: .animated(duration: 0.2, curve: .easeOut))
                }
            }
        }))
        
        return ActionDisposable { [weak self] in
            loadingStatuses.get(index)?.dispose()
            loadingStatuses.remove(index)
            if loadingStatuses.isEmpty {
                self?.updateStoryIndicator(transition: .animated(duration: 0.2, curve: .easeOut))
            }
        }
    }

    private func updateStoryIndicator(transition: ContainedViewLayoutTransition) {
        if let component = stateView.component, let availableSize = stateView.availableSize {
            stateView.update(component: component, availableSize: availableSize, progress: stateView.progress ?? 1.0, transition: transition, displayProgress: !self.loadingStatuses.isEmpty)
        }
    }

}

private final class ItemView : Control {
    fileprivate let imageView = AvatarControl(font: .avatar(15))
    fileprivate let smallImageView = AvatarControl(font: .avatar(7))
    fileprivate let textView = TextView()
    fileprivate let backgroundView = SimpleLayer()
    fileprivate var item: StoryListEntryRowItem?
    fileprivate var liveTextIndicator: ImageView?
    private var open:((StoryListEntryRowItem)->Void)?
    
    public weak var component: ComponentView?
    
    deinit {
    }
    
    public func setOpenProgress(_ signal:Signal<Never, NoError>) {
        SetOpenStoryDisposable(self.component?.pushLoadingStatus(signal: signal))
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.setFrameSize(StoryListChatListRowItem.fullSize)
        self.addSubview(textView)
        smallImageView.userInteractionEnabled = false
        imageView.userInteractionEnabled = false
        backgroundView.anchorPoint = .zero
        if #available(macOS 10.15, *) {
            backgroundView.cornerCurve = .continuous
        }
        self.layer?.addSublayer(backgroundView)
        self.addSubview(imageView)
        self.addSubview(smallImageView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isAccessibilityDecorative = true
        
        
        self.layer?.masksToBounds = false
        
        self.scaleOnClick = true
        
        self.contextMenu = { [weak self] in
            let menu = ContextMenu()
            if let signal = self?.item?.menuItems(in: .zero) {
                _ = signal.start(next: { [weak menu] items in
                    for item in items {
                        menu?.addItem(item)
                    }
                })
            }
            return menu
        }
        
        set(handler: { [weak self] _ in
            if let item = self?.item {
                self?.open?(item)
            }
        }, for: .Click)
        
        
    }
    
    public override func stateDidUpdate(_ state: ControlState) {
        super.stateDidUpdate(state)
        component?.stateDidUpdate(state)
    }

    override func accessibilityLabel() -> String? {
        return item?.accessibilityLabel ?? super.accessibilityLabel()
    }

    override func accessibilityValue() -> Any? {
        return item?.accessibilityValue
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func set(item: TableRowItem, open: @escaping(StoryListEntryRowItem)->Void, progress: CGFloat, animated: Bool) {
        
        let previous = self.item?.entry
        
        guard let item = item as? StoryListEntryRowItem else {
            return
        }
        
        self.open = open
        self.progress = progress
        self.item = item
        
        imageView.setPeer(account: item.context.account, peer: item.entry.item.peer._asPeer(), size: StoryListChatListRowItem.fullSize, disableForum: true)
        smallImageView.setPeer(account: item.context.account, peer: item.entry.item.peer._asPeer(), size: StoryListChatListRowItem.smallSize, disableForum: true)
        
        imageView.isHidden = progress == 0
        smallImageView.isHidden = progress != 0
        
        
        if previous?.name != item.entry.name {
            let layout = TextViewLayout(.initialize(string: item.entry.name.text, color: item.entry.name.color, font: .normal(10)), maximumNumberOfLines: 1, truncationType: .end)
            layout.measure(width: item.itemWidth + 5)
            textView.update(layout)
        }
        
        if item.entry.item.hasLiveItems {
            let current: ImageView
            let isNew: Bool
            if let view = self.liveTextIndicator {
                current = view
                isNew = false
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.addSubview(current)
                self.liveTextIndicator = current
                isNew = true
            }
            current.image = StoriesHooks.shared.generateLiveStreamBadge(9.5, theme.colors.background)
            current.sizeToFit()
            if isNew {
                current.centerX(y: imageView.frame.maxY - floorToScreenPixels(current.frame.height * 0.7))
            }
        } else if let view = liveTextIndicator {
            performSubviewRemoval(view, animated: animated)
            self.liveTextIndicator = nil
        }
        
        self.backgroundView.backgroundColor = theme.colors.background.cgColor
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate

        self.updateLayout(size: frame.size, transition: transition)
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    private var progress: CGFloat = 1.0
    
    public func set(progress: CGFloat, transition: ContainedViewLayoutTransition) {
        self.progress = progress
        
        imageView.isHidden = progress == 0
        smallImageView.isHidden = progress != 0

        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        guard let item = self.item else {
            return
        }
        
                
        let imageSize = NSMakeSize(size.width - 6 + (1 - progress) * (System.backingScale == 1.0 ? 2.0 : 1), size.width - 6 + (1 - progress) * (System.backingScale == 1.0 ? 2.0 : 1))

        let imageRect = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - imageSize.width) / 2), y: floorToScreenPixels(3 - (1 - progress) * 0.5)), size: imageSize)
        
        
        
        transition.updateFrame(view: imageView, frame: imageRect)
        transition.updateFrame(view: smallImageView, frame: imageRect)

        let inset: CGFloat = item.entry.hasUnseen ? 1.0 : 1.5
        transition.updateFrame(layer: backgroundView, frame: imageRect.insetBy(dx: -inset, dy: -inset))

        if let liveTextIndicator {
            transition.updateAlpha(view: liveTextIndicator, alpha: progress)
            transition.updateFrame(view: liveTextIndicator, frame: liveTextIndicator.centerFrameX(y: imageView.frame.maxY - floorToScreenPixels(liveTextIndicator.frame.height * 0.7)))
        }

        backgroundView.cornerRadius = backgroundView.frame.height / 2
        if transition.isAnimated {
            backgroundView.animateCornerRadius(duration: transition.duration, timingFunction: transition.timingFunction)
        }

        
        imageView.layer?.cornerRadius = imageView.frame.height / 2
        if transition.isAnimated {
            imageView.layer?.animateCornerRadius(duration: transition.duration, timingFunction: transition.timingFunction)
        }
        
        transition.updateTransformScale(layer: textView.layer!, scale: progress)
        transition.updateFrame(view: textView, frame: textView.centerFrameX(y: floorToScreenPixels(imageView.frame.maxY + 3 + (4.0 * progress)), addition: floorToScreenPixels((textView.frame.width * (1 - progress)) / 2)))
        transition.updateAlpha(view: textView, alpha: progress)
        
    }
    
}




