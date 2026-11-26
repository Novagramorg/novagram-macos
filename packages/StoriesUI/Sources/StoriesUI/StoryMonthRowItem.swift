import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InlineMediaGrid
import Localization

public final class StoryMonthRowItem : GeneralRowItem {
    private var contentHeight: CGFloat = 0
    fileprivate let items:[StoryListContextState.Item]
    fileprivate let context: any AccountContextProtocol
    fileprivate let peerReference: PeerReference
    fileprivate let peerId: PeerId

    fileprivate private(set) var layoutItems:[StoryCellLayoutItem] = []
    fileprivate private(set) var itemSize: NSSize = NSZeroSize
    fileprivate let standalone: Bool
    fileprivate let selected: Set<StoryId>?
    fileprivate let openStory:(StoryInitialIndex?)->Void
    fileprivate let toggleSelected: (StoryId)->Void
    fileprivate let menuItems: (StoryListContextState.Item)->[ContextMenuItem]
    fileprivate let pinnedIds:[Int32]
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let rowCountValue: Int
    fileprivate let nextRowCount: Int?
    fileprivate let clipsToPosts: Bool
    fileprivate private(set) var postsSize: NSSize = NSZeroSize
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, standalone: Bool, peerId: PeerId, peerReference: PeerReference, items: [StoryListContextState.Item], selected: Set<StoryId>?, pinnedIds:[Int32], rowCount: Int, nextRowCount: Int? = nil, clipsToPosts: Bool = false, viewType: GeneralViewType, openStory:@escaping(StoryInitialIndex?)->Void, toggleSelected: @escaping(StoryId)->Void, menuItems:@escaping(StoryListContextState.Item)->[ContextMenuItem], presentation: TelegramPresentationTheme = theme) {
        self.items = items
        self.selected = selected
        self.standalone = standalone
        self.peerReference = peerReference
        self.context = context
        self.peerId = peerId
        self.openStory = openStory
        self.toggleSelected = toggleSelected
        self.menuItems = menuItems
        self.pinnedIds = pinnedIds
        self.rowCountValue = rowCount
        self.nextRowCount = nextRowCount
        self.clipsToPosts = clipsToPosts
        self.presentation = presentation
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: standalone ? NSEdgeInsets(left: 20, right: 20) : NSEdgeInsets(), fullSize: !standalone)
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        for item in layoutItems {
            if NSPointInRect(location, item.frame) {
                return .single(self.menuItems(item.item))
            }
        }
        return super.menuItems(in: location)
    }
    
    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonStories
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return layoutItems.map { layoutItem in
            let peerId = layoutItem.peerId
            let storyId = layoutItem.item.storyItem.id
            let name = strings().voiceOverCommonStory + ", " + stringForFullDate(timestamp: layoutItem.item.storyItem.timestamp)
            return NSAccessibilityCustomAction(name: name, handler: { [weak self] in
                self?.openPeerStory(peerId: peerId, storyId: storyId)
                return true
            })
        }
    }

    public func openPeerStory(peerId: PeerId, storyId: Int32) {
        let table = self.table
        self.openStory(.init(peerId: peerId, id: storyId, messageId: nil, takeControl: { [weak table] peerId, _, storyId in
            return StoryMonthRowItem.takeControl(in: table, peerId: peerId, storyId: storyId)
        }))
    }
    
    fileprivate static func takeControl(in table: TableView?, peerId: PeerId, storyId: Int32?) -> NSView? {
        guard let table = table else {
            return nil
        }
        var found: StoryMonthRowItem?
        table.enumerateItems(with: { item in
            if let item = item as? StoryMonthRowItem, item.layoutItems.contains(where: { $0.peerId == peerId && (storyId == nil || $0.id.id == storyId) }) {
                found = item
            }
            return found == nil
        })
        guard let item = found else {
            return nil
        }
        if let view = table.viewNecessary(at: item.index) as? StoryMonthRowView, let control = view.takeControl(peerId, storyId: storyId), StoryMorphEndpoint.visibleFraction(of: control) >= 0.5 {
            return control
        }
        table.scroll(to: .center(id: item.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: 0), toVisible: true)
        guard let view = table.viewNecessary(at: item.index) as? StoryMonthRowView else {
            return nil
        }
        view.layoutSubtreeIfNeeded()
        return view.takeControl(peerId, storyId: storyId)
    }
    
    public override func viewClass() -> AnyClass {
        return StoryMonthRowView.self
    }
    
    public override var canBeAnchor: Bool {
        return true
    }
    
    public static func rowCount(blockWidth: CGFloat, rowCount: Int, viewType: GeneralViewType) -> (Int, CGFloat) {
        var perWidth: CGFloat = 7
        var rowCount = rowCount
        while true {
            let maximum = blockWidth - viewType.innerInset.left - viewType.innerInset.right - CGFloat(rowCount * 2)
            perWidth = maximum / CGFloat(rowCount)
            if perWidth >= 90 {
                break
            } else {
                rowCount -= 1
            }
        }
        return (rowCount, perWidth)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        
        let (rowCount, perWidth) = StoryMonthRowItem.rowCount(blockWidth: self.blockWidth, rowCount: rowCountValue, viewType: self.viewType)
        
        assert(rowCount >= 1)
                
        let itemSize = NSMakeSize(ceil(perWidth) + 2, ceil(perWidth * 1.36) + 2)
        
        layoutItems.removeAll()
        var point: CGPoint = CGPoint(x: self.viewType.innerInset.left, y: self.viewType.innerInset.top + itemSize.height)
        for (i, item) in self.items.enumerated() {
            let viewType: MediaCell.Type
            viewType = (item.storyItem.media._asMedia() is TelegramMediaFile) ? MediaVideoCell.self : MediaPhotoCell.self

            
            var topLeft: ImageCorner = .Corner(0)
            var topRight: ImageCorner = .Corner(0)
            var bottomLeft: ImageCorner = .Corner(0)
            var bottomRight: ImageCorner = .Corner(0)
            
            if self.viewType.position != .first && self.viewType.position != .inner {
                if self.items.count < rowCount {
                    if item == self.items.first {
                        if self.viewType.position != .last {
                            topLeft = .Corner(.cornerRadius)
                        }
                        bottomLeft = .Corner(.cornerRadius)
                    }
                } else if self.items.count == rowCount {
                    if item == self.items.first {
                        if self.viewType.position != .last {
                            topLeft = .Corner(.cornerRadius)
                        }
                        bottomLeft = .Corner(.cornerRadius)
                    } else if item == self.items.last {
                        if item == self.items.last {
                            if self.viewType.position != .last {
                                topRight = .Corner(.cornerRadius)
                            }
                            bottomRight = .Corner(.cornerRadius)
                        }
                    }
                } else {
                    let i = i + 1
                    let firstLine = i <= rowCount
                    let div = (items.count % rowCount) == 0 ? rowCount : (items.count % rowCount)
                    let lastLine = i > (items.count - div)
                    
                    if firstLine {
                        if self.viewType.position != .last {
                            if i % rowCount == 1 {
                                topLeft = .Corner(.cornerRadius)
                            } else if i % rowCount == 0 {
                                topRight = .Corner(.cornerRadius)
                            }
                        }
                    } else if lastLine {
                        if i % rowCount == 1 {
                            bottomLeft = .Corner(.cornerRadius)
                        } else if i % rowCount == 0 {
                            bottomRight = .Corner(.cornerRadius)
                        }
                    }
                }
            }
            let corners = ImageCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
            
            let peerId = item.id.peerId
            let peerReference = item.peer.flatMap { peer -> PeerReference? in
                guard peer.id == peerId else {
                    return nil
                }
                return PeerReference(peer._asPeer())
            } ?? self.peerReference
            let cell = StoryCellLayoutItem(item: item, peerReference: peerReference, peerId: peerId, frame: CGRect(origin: point.offsetBy(dx: 0, dy: -itemSize.height), size: itemSize), viewType: viewType, corners: corners, context: context, isPinned: self.pinnedIds.contains(item.storyItem.id))
            
            self.layoutItems.append(cell)
            point.x += itemSize.width
            if self.layoutItems.count % rowCount == 0, item != self.items.last {
                point.y += itemSize.height
                point.x = self.viewType.innerInset.left
            }
        }
        self.postsSize = NSMakeSize((self.layoutItems.map { $0.frame.maxX }.max() ?? 1) - 1, point.y)
        self.itemSize = itemSize
        self.contentHeight = point.y - self.viewType.innerInset.top
        return true
    }
    
    fileprivate var gridCorners: GeneralViewItemCorners {
        if let nextRowCount = self.nextRowCount, nextRowCount < self.items.count {
            return self.viewType.corners.union(.bottomRight)
        }
        return self.viewType.corners
    }
    
    public func contains(_ id: Int32) -> Bool {
        return layoutItems.contains(where: { $0.item.storyItem.id == id} )
    }
    
    public override var height: CGFloat {
        return self.contentHeight + self.viewType.innerInset.top + self.viewType.innerInset.bottom + 1
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    deinit {

    }
}


private final class StoryMonthRowView : GeneralContainableRowView, Notifable {
    private var contentViews:[Optional<MediaCell>] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        containerView.set(handler: { [weak self] _ in
            self?.action(event: .Down)
        }, for: .Down)
        
        containerView.set(handler: { [weak self] _ in
            self?.action(event: .MouseDragging)
        }, for: .MouseDragging)
        
        containerView.set(handler: { [weak self] _ in
            self?.action(event: .Click)
        }, for: .Click)
    }
    
    
    private weak var currentMouseCell: MediaCell?
    
    @objc func _updateMouse() {
        self.updateMouse(animated: true)
        guard let window = self.window else {
            return
        }
        let point = self.containerView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let mediaCell = self.contentViews.first(where: {
            return $0 != nil && NSPointInRect(point, $0!.frame)
        })?.map { $0 }
        
        if currentMouseCell != mediaCell {
            currentMouseCell?.updateMouse(false)
        }
        currentMouseCell = mediaCell
        mediaCell?.updateMouse(window.isKeyWindow)
        
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        _updateMouse()
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        _updateMouse()
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        _updateMouse()
    }
    
    private func action(event: ControlEvent) {
        guard let item = self.item as? StoryMonthRowItem, let window = window else {
            return
        }
        if event == .Click {
            let point = containerView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            for contentView in contentViews {
                if let contentView = contentView, let layoutItem = contentView.layoutItem {
                    if NSPointInRect(point, contentView.frame) {
                        
                        if item.selected != nil {
                            item.toggleSelected(.init(peerId: layoutItem.peerId, id: layoutItem.id.id))
                        } else {
                            item.openPeerStory(peerId: layoutItem.peerId, storyId: layoutItem.id.id)
                        }
                        return
                    }
                }
            }
            
            
        }
    }
    
    fileprivate func takeControl(_ peerId: PeerId, storyId: Int32?) -> NSView? {
        for contentView in contentViews {
            if let layoutItem = contentView?.layoutItem {
                if layoutItem.peerId == peerId, storyId == nil || layoutItem.id.id == storyId {
                    return contentView
                }
            }
        }
        return nil
    }
    
    func notify(with value: Any, oldValue:Any, animated:Bool) {
        
    }
    
    func isEqual(to other: Notifable) -> Bool {
        if let other = other as? StoryMonthRowView {
            return other == self
        }
        return false
    }
       
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        guard let item = item as? StoryMonthRowItem else {
            return theme.colors.background
        }
        return item.standalone ? item.presentation.colors.background : .clear
    }
    
    override func updateColors() {
        super.updateColors()
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateVisibleItems()
    }
    
    @objc private func updateVisibleItems() {
        
    }
    
    private var previousRange: (Int, Int) = (0, 0)
    private func layoutVisibleItems(animated: Bool) {
        guard let item = item as? StoryMonthRowItem else {
            return
        }
                
        CATransaction.begin()
        for (i, layout) in item.layoutItems.enumerated() {
            var view: MediaCell
            if self.contentViews[i] == nil || !self.contentViews[i]!.isKind(of: layout.viewType) {
                view = layout.viewType.init(frame: layout.frame)
                self.contentViews[i] = view
            } else {
                view = self.contentViews[i]!
            }
            let selected: Bool?
            if let state = item.selected {
                selected = state.contains(.init(peerId: layout.peerId, id: layout.item.storyItem.id))
            } else {
                selected = nil
            }
            view.update(layout: layout, selected: selected, context: item.context, table: item.table, animated: animated)

            view.frame = layout.frame
        }
        
        containerView.subviews = self.contentViews.compactMap { $0 }

        CATransaction.commit()
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
         if window == nil {
             NotificationCenter.default.removeObserver(self)
         } else {
             NotificationCenter.default.addObserver(self, selector: #selector(updateVisibleItems), name: NSView.boundsDidChangeNotification, object: self.enclosingScrollView?.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(_updateMouse), name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(_updateMouse), name: NSWindow.didResignKeyNotification, object: nil)
         }
         updateVisibleItems()
     }
    
    override func layout() {
        super.layout()
        updateVisibleItems()
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = item as? StoryMonthRowItem, item.clipsToPosts, !item.viewType.isPlainMode else {
            return
        }
        let containerSize = containerView.frame.size
        containerView.setCorners(item.gridCorners, animated: transition.isAnimated, frame: NSMakeRect(0, 0, min(containerSize.width, item.postsSize.width), min(containerSize.height, item.postsSize.height)))
    }
    
    override func interactionContentView(for innerId: AnyHashable, animateIn: Bool) -> NSView {
        return mediaCellInteractionContentView(contentViews, for: innerId, fallback: self)
    }
    
    override func addAccesoryOnCopiedView(innerId: AnyHashable, view: NSView) {
        addMediaCellAccesoryOnCopiedView(contentViews, innerId: innerId, view: view)
    }
    
    override func convertWindowPointToContent(_ point: NSPoint) -> NSPoint {
        return containerView.convert(point, from: nil)
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        
        super.set(item: item, animated: animated)
        
        guard let item = item as? StoryMonthRowItem else {
            return
        }
        
        self.previousRange = (0, 0)
        
        while self.contentViews.count > item.layoutItems.count {
            self.contentViews.removeLast()
        }
        while self.contentViews.count < item.layoutItems.count {
            self.contentViews.append(nil)
        }
        
        layoutVisibleItems(animated: animated)
    }
}

