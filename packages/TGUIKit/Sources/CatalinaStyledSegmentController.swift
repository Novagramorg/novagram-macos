import Cocoa
import AppKit

public class CatalinaSegmentedItem {
    let title:String
    let handler: ()->Void
    public init(title:String, handler:@escaping()->Void) {
        self.title = title
        self.handler = handler
    }
}


public struct CatalinaSegmentTheme {
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let activeTextColor: NSColor
    let inactiveTextColor: NSColor
    public init(backgroundColor: NSColor, foregroundColor: NSColor, activeTextColor: NSColor, inactiveTextColor: NSColor) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.activeTextColor = activeTextColor
        self.inactiveTextColor = inactiveTextColor
    }
}

private final class CatalinaSegmentItemView : Control {
    let item: CatalinaSegmentedItem
    private let inactiveTextView: TextView = TextView()
    private let activeTextView: TextView = TextView()
    private let separatorView = View()

    /// Width the title needs without truncation. Cached so layout passes
    /// don't re-measure on every call.
    fileprivate private(set) var naturalTextWidth: CGFloat = 0
    init(item: CatalinaSegmentedItem, theme: CatalinaSegmentTheme, select:@escaping()->Void) {
        self.item = item
        self.theme = theme
        super.init(frame: NSZeroRect)
        addSubview(activeTextView)
        addSubview(inactiveTextView)
        addSubview(separatorView)
        activeTextView.userInteractionEnabled = false
        activeTextView.isSelectable = false
        
        inactiveTextView.userInteractionEnabled = false
        inactiveTextView.isSelectable = false
        scaleOnClick = true
        
        set(handler: { _ in
            select()
        }, for: .SingleClick)
        
    }
    
    
    var theme: CatalinaSegmentTheme {
        didSet {
            update()
            needsLayout = true
        }
    }
    
    private func update() {

        activeTextView.disableBackgroundDrawing = true
        inactiveTextView.disableBackgroundDrawing = true

        let activeLayout = TextViewLayout(.initialize(string: item.title, color: theme.activeTextColor, font: .medium(.text)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        activeLayout.measure(width: frame.width - 6)

        let inactiveLayout = TextViewLayout(.initialize(string: item.title, color: theme.inactiveTextColor, font: .normal(.text)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        inactiveLayout.measure(width: frame.width - 6)

        // The active (medium) variant is the wider of the two — track it so
        // fit-content layout can size each item without re-measuring text.
        let unconstrained = TextViewLayout(.initialize(string: item.title, color: theme.activeTextColor, font: .medium(.text)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        unconstrained.measure(width: .greatestFiniteMagnitude)
        naturalTextWidth = unconstrained.layoutSize.width

        activeTextView.update(activeLayout)
        inactiveTextView.update(inactiveLayout)

        separatorView.backgroundColor = theme.inactiveTextColor

    }
    
    func set(_ selected: Bool, hasSepator: Bool, animated: Bool) {
        separatorView.change(opacity: hasSepator ? 0.4 : 0, animated: animated)
        activeTextView.change(opacity: selected ? 1 : 0, animated: animated)
        inactiveTextView.change(opacity: !selected ? 1 : 0, animated: animated)
        
//        activeTextView.backgroundColor = !selected ? theme.backgroundColor : theme.foregroundColor
//        inactiveTextView.backgroundColor = !selected ? theme.backgroundColor : theme.foregroundColor

      //  userInteractionEnabled = !selected
        isSelected = selected
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        update()
        separatorView.frame = NSMakeRect(frame.width - .borderSize, 8, .borderSize, frame.height - 16)
        activeTextView.center()
        inactiveTextView.center()
        
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
    }
}

private class CatalinaSegmentedControlView: View {
    private let button: Control = Control()
    private let itemsContainerView = View()

    /// When true, every item is sized to its title's natural width plus
    /// `fitContentHorizontalPadding`, and items pack starting from the left
    /// of `itemsContainerView`. When false (default), items split the bar
    /// evenly — the original behavior every existing callsite relies on.
    fileprivate var fitContent: Bool = false {
        didSet {
            // Fit-content mode uses fully-rounded corners on both the bar and
            // the selected pill so a single-item segment doesn't look like a
            // truncated rectangle. The legacy mode keeps its original 10/8
            // radii to avoid visual churn elsewhere.
            applyCornerRadius()
            needsLayout = true
        }
    }
    fileprivate var fitContentHorizontalPadding: CGFloat = 24

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 10.0
        addSubview(button)
        addSubview(itemsContainerView)
        button.layer?.cornerRadius = 8

    }

    private func applyCornerRadius() {
        if fitContent {
            let outer = frame.height / 2
            layer?.cornerRadius = outer
            button.layer?.cornerRadius = max(0, outer - 2)
        } else {
            layer?.cornerRadius = 10
            button.layer?.cornerRadius = 8
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var theme: CatalinaSegmentTheme = CatalinaSegmentTheme(backgroundColor: presentation.colors.listBackground, foregroundColor: presentation.colors.background, activeTextColor: presentation.colors.text, inactiveTextColor: presentation.colors.listGrayText) {
        didSet {
            for subview in itemsContainerView.subviews.compactMap({ $0 as? CatalinaSegmentItemView}) {
                subview.theme = theme
            }
            update()
        }
    }
    
    private func update() {
        // Background is transparent in both modes — the selected-item pill
        // (`button`) provides all the visible chrome. Callers that need a
        // tinted track can layer this view over their own background.
        self.backgroundColor = .clear
        itemsContainerView.backgroundColor = .clear

        button.backgroundColor = theme.foregroundColor
        needsLayout = true
    }
    
    func update(items: [CatalinaSegmentedItem], selected: Int, animated: Bool, select: @escaping(Int, Bool)->Void) -> Void {
        itemsContainerView.removeAllSubviews()
        for i in 0 ..< items.count {
            let view = CatalinaSegmentItemView(item: items[i], theme: theme, select: { select(i, true) })
            var hasSeparator: Bool = false
            if i != (items.count - 1) && selected != i {
                hasSeparator = true
                if selected > 0 {
                    if i == selected - 1 {
                        hasSeparator = false
                    }
                }
            }
            view.set(selected == i, hasSepator: hasSeparator, animated: animated)
            itemsContainerView.addSubview(view)
        }
        
        needsLayout = true
    }
    
    func set(selected: Int, animated: Bool) {
        let items = self.itemsContainerView.subviews.compactMap { $0 as? CatalinaSegmentItemView }
        for (i, subview) in items.enumerated() {
            var hasSeparator: Bool = false
            if i != (items.count - 1) && selected != i {
                hasSeparator = true
                if selected > 0 {
                    if i == selected - 1 {
                        hasSeparator = false
                    }
                }
            }
            subview.set(selected == i, hasSepator: hasSeparator, animated: animated)
            if selected == i {
                button.change(pos: NSMakePoint(max(2, min(subview.frame.minX + 2, frame.width - subview.frame.width - 2)), 2), animated: animated)
            }
        }
        needsLayout = true
    }
    
    /// Sum of all item natural widths plus padding — what `fitContent` mode
    /// wants the bar to be. Callers use this to size the outer segment frame
    /// without re-measuring text themselves.
    fileprivate var intrinsicContentWidth: CGFloat {
        let items = self.itemsContainerView.subviews.compactMap { $0 as? CatalinaSegmentItemView }
        guard !items.isEmpty else { return 0 }
        var total: CGFloat = 0
        for view in items {
            total += view.naturalTextWidth + fitContentHorizontalPadding
        }
        return total
    }

    override func layout() {
        super.layout()

        applyCornerRadius()

        let items = self.itemsContainerView.subviews.compactMap { $0 as? CatalinaSegmentItemView }

        guard !items.isEmpty else { return }

        self.itemsContainerView.frame = bounds

        if fitContent {
            // Each item gets its natural width (text + padding). If the sum
            // would overflow the bar we shrink proportionally; if the bar is
            // wider than the items need (caller enforces a minimum bar width)
            // we center the items so they don't look stuck to the left edge.
            var naturalWidths: [CGFloat] = []
            naturalWidths.reserveCapacity(items.count)
            var total: CGFloat = 0
            for view in items {
                let w = view.naturalTextWidth + fitContentHorizontalPadding
                naturalWidths.append(w)
                total += w
            }
            var scale: CGFloat = 1
            if total > frame.width && total > 0 {
                scale = frame.width / total
            }
            let scaledTotal = total * scale
            var x: CGFloat = max(0, (frame.width - scaledTotal) / 2)

            let selectedPillSideInset: CGFloat = 6
            for (i, view) in items.enumerated() {
                let w = naturalWidths[i] * scale
                view.frame = NSMakeRect(x, 0, w, frame.height)
                if view.isSelected {
                    let pillX = max(selectedPillSideInset, x + selectedPillSideInset)
                    let pillW = max(0, w - selectedPillSideInset * 2)
                    button.frame = NSMakeRect(pillX, 2, pillW, frame.height - 4)
                }
                x += w
            }
        } else {
            var x: CGFloat = 0
            var itemWidth = floor(frame.width / CGFloat(items.count))
            if itemWidth == frame.width {
                itemWidth = frame.width - 4
            }
            for view in items {
                view.frame = NSMakeRect(x, 0, itemWidth, frame.height)

                if view.isSelected {
                    button.frame = NSMakeRect(max(2, min(x + 2, frame.width - itemWidth - 2)), 2, itemWidth, frame.height - 4)
                }

                x += itemWidth
            }
        }
    }

}


public class CatalinaStyledSegmentController: ViewController {
    private var items: [CatalinaSegmentedItem] = []
    private var selected: Int = 0
    
    private var genericView: CatalinaSegmentedControlView {
        return self.view as! CatalinaSegmentedControlView
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bar = .init(height: 0)
    }
    
    public var theme: CatalinaSegmentTheme {
        get {
            return genericView.theme
        }
        set {
            genericView.theme = newValue
        }
    }

    /// When true, items size to their title widths instead of dividing the
    /// bar equally. Callers should also size the outer frame to
    /// `intrinsicContentWidth` (or clamp it) for a clean look.
    public var fitContent: Bool {
        get { return genericView.fitContent }
        set { genericView.fitContent = newValue }
    }

    public var fitContentHorizontalPadding: CGFloat {
        get { return genericView.fitContentHorizontalPadding }
        set { genericView.fitContentHorizontalPadding = newValue }
    }

    public var intrinsicContentWidth: CGFloat {
        return genericView.intrinsicContentWidth
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }
    
    public var count: Int {
        return self.items.count
    }
    
    private func select(_ index: Int, animated: Bool) {
        self.selected = index
        items[index].handler()
        genericView.set(selected: index, animated: animated)
    }
    
    public func add(segment: CatalinaSegmentedItem) -> Void {
        items.append(segment)
        genericView.update(items: items, selected: selected, animated: false, select: { [weak self] index, animated in
            self?.select(index, animated: animated)
        })
    }
    
    public func set(items: [CatalinaSegmentedItem]) -> Void {
        self.items = items
        genericView.update(items: items, selected: selected, animated: false, select: { [weak self] index, animated in
            self?.select(index, animated: animated)
        })
    }
    
    public func segment(at index:Int) -> CatalinaSegmentedItem {
        return items[index]
    }
    public func replace(segment: CatalinaSegmentedItem, at index:Int) -> Void {
       items[index] = segment
        genericView.update(items: items, selected: selected, animated: false, select: { [weak self] index, animated in
            self?.select(index, animated: animated)
        })
    }
    public func insert(segment: CatalinaSegmentedItem, at index: Int) -> Void {
        items.insert(segment, at: index)
        genericView.update(items: items, selected: selected, animated: false, select: { [weak self] index, animated in
            self?.select(index, animated: animated)
        })
    }
    public func remove(at index: Int) -> Void {
        items.remove(at: index)
        genericView.update(items: items, selected: selected, animated: false, select: { [weak self] index, animated in
            self?.select(index, animated: animated)
        })
    }
    
    public func set(selected index: Int, animated: Bool = false) -> Void {
        selected = index
        genericView.set(selected: index, animated: animated)
    }
    
    public func selectNext(animated: Bool) {
        var index = self.selected
        index += 1
        if index == self.items.count {
            index = 0
        }
        self.select(index, animated: animated)
    }
    
    public func removeAll() -> Void {
        selected = 0
        items.removeAll()
        genericView.update(items: items, selected: selected, animated: false, select: { [weak self] index, animated in
            self?.select(index, animated: animated)
        })
    }
    
    override public func viewClass() -> AnyClass {
        return CatalinaSegmentedControlView.self
    }
}
