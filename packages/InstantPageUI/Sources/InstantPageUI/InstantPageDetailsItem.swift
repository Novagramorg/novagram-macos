import Cocoa
import Foundation
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import Postbox
import TelegramCore

import TGUIKit
import TelegramContext
import AudioPlayerCore
import SwiftSignalKit
import RangeSet

public final class InstantPageDetailsItem: InstantPageItem {
    public var hasLinks: Bool = false
    
    public var isInteractive: Bool = false
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public var frame: CGRect
    public let wantsView: Bool = true
    public let separatesTiles: Bool = true
    public let medias: [InstantPageMedia] = []
    
    public let titleItems: [InstantPageItem]
    public let titleHeight: CGFloat
    public let items: [InstantPageItem]
    public let safeInset: CGFloat
    public let rtl: Bool
    public let initiallyExpanded: Bool
    public let index: Int
    
    public var isExpanded: Bool {
        return self.arguments?.isExpandedItem(self) ?? initiallyExpanded
    }
    
    public var effectiveRect: NSRect {
        return self.arguments?.effectiveRectForItem(self) ?? frame
    }
    
    private var arguments: InstantPageItemArguments?
    
    public init(frame: CGRect, titleItems: [InstantPageItem], titleHeight: CGFloat, items: [InstantPageItem], safeInset: CGFloat, rtl: Bool, initiallyExpanded: Bool, index: Int) {
        self.frame = frame
        self.titleItems = titleItems
        self.titleHeight = titleHeight
        self.items = items
        self.safeInset = safeInset
        self.rtl = rtl
        self.initiallyExpanded = initiallyExpanded
        self.index = index
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        var expanded: Bool?
        self.arguments = arguments
        if let expandedDetails = currentExpandedDetails, let currentlyExpanded = expandedDetails[self.index] {
            expanded = currentlyExpanded
        }
        return InstantPageDetailsView(arguments: arguments, item: self, currentlyExpanded: expanded)
    }
    
    private func itemsIn( _ rect: NSRect, items: [InstantPageItem] = []) -> [InstantPageItem] {
        var items: [InstantPageItem] = items
        for (_, item) in self.items.enumerated() {
            if  item.frame.intersects(rect) {
                if let item = item as? InstantPageTableItem {
                    return item.itemsIn(rect, items: items)
                } else if let item = item as? InstantPageDetailsItem {
                    var rect = rect
                    rect.origin.y = rect.minY - item.effectiveRect.minY - titleHeight
                    return item.itemsIn(rect, items: items)
                } else {
                    items.append(item)
                }
            }
            
        }
        return items
    }
    public func itemsIn( _ rect: NSRect) -> [InstantPageItem] {
        return self.itemsIn(rect.offsetBy(dx: 0, dy: -titleHeight), items: [])
    }
    
    public func deepRect(_ rect: NSRect) -> NSRect {
        for (_, item) in self.items.enumerated() {
            if item.frame.intersects(rect) {
                if let item = item as? InstantPageDetailsItem {
                    var rect = rect
                    let result = rect.minY - item.effectiveRect.minY - titleHeight
                    rect.origin.y = result
                    if result > 0 {
                        
                        return item.deepRect(rect)

                    } else {
                        var bp:Int = 0
                        bp += 1
                    }
                }
            }
            
        }
        return rect
    }
    
    public func deepItemsInRect(_ rect: NSRect, items: [InstantPageItem] = []) -> [InstantPageItem] {
        for (_, item) in self.items.enumerated() {
            if  item.frame.intersects(rect) {
                if let item = item as? InstantPageDetailsItem {
                    var rect = rect
                    rect.origin.y = rect.minY - item.effectiveRect.minY - titleHeight
                    return item.deepItemsInRect(rect, items: item.items)
                }
            }
            
        }
        return items
    }
    
    public func deepItemsInRect(_ rect: NSRect) -> [InstantPageItem] {
        return deepItemsInRect(rect, items: self.items)
    }
    

    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func matchesView(_ node: InstantPageView) -> Bool {
        if let node = node as? InstantPageDetailsView {
            return self === node.item
        } else {
            return false
        }
    }
    
    public func distanceThresholdGroup() -> Int? {
        return 8
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        return CGFloat.greatestFiniteMagnitude
    }
    
    public func drawInTile(context: CGContext) {
    }
    
    
}

public func layoutDetailsItem(theme: InstantPageTheme, title: NSAttributedString, boundingWidth: CGFloat, items: [InstantPageItem], contentSize: CGSize, safeInset: CGFloat, rtl: Bool, initiallyExpanded: Bool, index: Int) -> InstantPageDetailsItem {
    let detailsInset: CGFloat = 17.0 + safeInset
    let titleInset: CGFloat = 22.0
    
    let (_, titleItems, titleSize) = layoutTextItemWithString(title, boundingWidth: boundingWidth - detailsInset * 2.0 - titleInset, offset: CGPoint(x: detailsInset + titleInset, y: 0.0))
    let titleHeight = max(44.0, titleSize.height + 26.0)
    var offset: CGFloat?
    for var item in titleItems {
        var itemOffset = floorToScreenPixels(System.backingScale, (titleHeight - item.frame.height) / 2.0)
        if item is InstantPageTextItem {
            offset = itemOffset
        } else if let offset = offset {
            itemOffset = offset
        }
        item.frame = item.frame.offsetBy(dx: 0.0, dy: itemOffset)
    }
    
    return InstantPageDetailsItem(frame: CGRect(x: 0.0, y: 0.0, width: boundingWidth, height: contentSize.height + titleHeight), titleItems: titleItems, titleHeight: titleHeight, items: items, safeInset: safeInset, rtl: rtl, initiallyExpanded: initiallyExpanded, index: index)
}










private let detailsInset: CGFloat = 17.0
private let titleInset: CGFloat = 22.0

public final class InstantPageDetailsView: Control, InstantPageView {
    private let arguments: InstantPageItemArguments
    public let item: InstantPageDetailsItem
    
    private let titleTile: InstantPageTile
    private let titleTileView: InstantPageTileView
    
    private let highlightedBackgroundView: View
    private let buttonView: Control
    private let arrowView: InstantPageDetailsArrowView
    public let separatorView: View
    public let contentView: InstantPageContentView
    
    public var expanded: Bool
    
    public var previousView: InstantPageDetailsView?
    
    public var requestLayoutUpdate: ((Bool) -> Void)?
    
    public init(arguments: InstantPageItemArguments, item: InstantPageDetailsItem, currentlyExpanded: Bool?) {
        self.arguments = arguments
       
        self.item = item
        
        
        let frame = item.frame
        
        self.highlightedBackgroundView = View()
        self.highlightedBackgroundView.layer?.opacity = 0.0
        
        
        self.titleTile = InstantPageTile(frame: CGRect(x: 0.0, y: 0.0, width: frame.width, height: item.titleHeight))
        self.titleTile.items.append(contentsOf: item.titleItems)
        self.titleTileView = InstantPageTileView(tile: self.titleTile, backgroundColor: .clear)
        
        if let expanded = currentlyExpanded {
            self.expanded = expanded
        } else {
            self.expanded = item.initiallyExpanded
        }
        
        self.arrowView = InstantPageDetailsArrowView(color: theme.colors.grayText, open: self.expanded)
        self.separatorView = View()
        separatorView.backgroundColor = theme.colors.border
        self.buttonView = Control()
        
        self.contentView = InstantPageContentView(arguments: arguments, items: item.items, contentSize: CGSize(width: item.frame.width, height: item.frame.height - item.titleHeight))
        
        
        
        super.init()
        
        
        self.addSubview(self.contentView)
        self.addSubview(self.highlightedBackgroundView)
        self.addSubview(self.titleTileView)
        self.addSubview(self.arrowView)
        self.addSubview(self.separatorView)
        self.addSubview(self.buttonView)

       
        
        buttonView.set(handler: { [weak self] _ in
            guard let `self` = self else {return}
            arguments.updateDetailsExpanded(!self.expanded)
            self.setExpanded(!self.expanded, animated: true)
        }, for: .Click)
        
        self.contentView.requestLayoutUpdate = { [weak self] animated in
            self?.requestLayoutUpdate?(animated)
        }
        self.setExpanded(self.expanded, animated: false)

    }
    

    public override var needsDisplay: Bool {
        didSet {
            for subview in self.contentView.subviews {
                subview.needsDisplay = true
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    public func setExpanded(_ expanded: Bool, animated: Bool) {
        self.expanded = expanded
        self.arrowView.setOpen(expanded, animated: animated)
        self.buttonView.setAccessibilityLabel(item.titleItems.compactMap { ($0 as? InstantPageTextItem)?.attributedString.string }.joined(separator: " "))
        self.buttonView.setAccessibilityExpanded(expanded)
    }
    
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
    }
    
    public override func layout() {
        super.layout()
        
        let size = self.bounds.size
        let inset = detailsInset + self.item.safeInset
        
        self.titleTileView.frame = self.titleTile.frame
        self.highlightedBackgroundView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: size.width, height: self.item.titleHeight + .borderSize))
        self.buttonView.frame = CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: self.item.titleHeight))
        self.arrowView.frame = CGRect(x: inset, y: floorToScreenPixels(backingScaleFactor, (self.item.titleHeight - 8.0) / 2.0) + 1.0, width: 13.0, height: 8.0)
        self.contentView.frame = CGRect(x: 0.0, y: self.item.titleHeight, width: size.width, height: self.item.frame.height - self.item.titleHeight)
        
        let lineSize = CGSize(width: self.frame.width - inset, height: .borderSize)
        self.separatorView.frame = CGRect(origin: CGPoint(x: self.item.rtl ? 0.0 : inset, y: self.item.titleHeight - lineSize.height), size: lineSize)
    }
    
    public func updateIsVisible(_ isVisible: Bool) {
        
    }
    
    
    public func updateVisibleItems(visibleBounds: CGRect, animated: Bool) {
        if self.bounds.height > self.item.titleHeight {
            self.contentView.updateVisibleItems(visibleBounds: visibleBounds.offsetBy(dx: -self.contentView.frame.minX, dy: -self.contentView.frame.minY), animated: animated)
        }
    }
    
    public func textItemAtLocation(_ location: CGPoint) -> (InstantPageTextItem, CGPoint)? {
        if self.titleTileView.frame.contains(location) {
            for case let item as InstantPageTextItem in self.item.titleItems {
                if item.frame.contains(location) {
                    return (item, self.titleTileView.frame.origin)
                }
            }
        }
        else if let (textItem, parentOffset) = self.contentView.textItemAtLocation(location.offsetBy(dx: -self.contentView.frame.minX, dy: -self.contentView.frame.minY)) {
            return (textItem, self.contentView.frame.origin.offsetBy(dx: parentOffset.x, dy: parentOffset.y))
        }
        return nil
    }
    
    
    public var effectiveContentSize: CGSize {
        return self.contentView.effectiveContentSize
    }
    
    public func effectiveFrameForItem(_ item: InstantPageItem) -> CGRect {
        return self.contentView.effectiveFrameForItem(item).offsetBy(dx: 0.0, dy: self.item.titleHeight)
    }
}


public final class InstantPageDetailsArrowView : View {
    public var color: NSColor {
        didSet {
            self.setNeedsDisplay()
        }
    }
    private(set) var open: Bool
    
    private var progress: CGFloat = 0.0
    private var targetProgress: CGFloat?
    private var animator: ConstantDisplayLinkAnimator?
    
    public init(color: NSColor, open: Bool) {
        self.color = color
        self.open = open
        self.progress = open ? 1.0 : 0.0
        
        super.init()
    
        
       
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    deinit {
        animator?.invalidate()
    }
    
    private func stopTimer() {
        animator?.isPaused = true
        animator = nil
    }
    private func startTimer() {
        if animator == nil {
            let animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] duration in
                self?.displayLinkEvent(duration)
            })
            animator.isPaused = false
            self.animator = animator
        }
    }
    
    public func setOpen(_ open: Bool, animated: Bool) {
        self.open = open
        let openProgress: CGFloat = open ? 1.0 : 0.0
        if animated {
            self.targetProgress = openProgress
            startTimer()
        } else {
            self.progress = openProgress
            self.targetProgress = nil
            stopTimer()
        }
    }
    
    
    private func displayLinkEvent(_ duration: CGFloat) {
        if let targetProgress = self.targetProgress {
            let sign = CGFloat(targetProgress - self.progress > 0 ? 1 : -1)
            self.progress += 0.14 * duration / 0.016 * sign
            if sign > 0 && self.progress > targetProgress {
                self.progress = 1.0
                self.targetProgress = nil
                 stopTimer()
               //self.displayLink?.isPaused = true
            } else if sign < 0 && self.progress < targetProgress {
                self.progress = 0.0
                self.targetProgress = nil
                stopTimer()
            }
        }
        
        self.setNeedsDisplay()
    }
    
  
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(2.0)
        
        ctx.move(to: CGPoint(x: 1.0, y: 1.0 + 5.0 * progress))
        ctx.addLine(to: CGPoint(x: 6.0, y: 6.0 - 5.0 * progress))
        ctx.addLine(to: CGPoint(x: 11.0, y: 1.0 + 5.0 * progress))
        ctx.strokePath()
    }
    
}
