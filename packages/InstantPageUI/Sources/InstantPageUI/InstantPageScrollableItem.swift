import Cocoa

import Foundation
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import TelegramCore
import SwiftSignalKit
import RangeSet

import Postbox
import TGUIKit
import TelegramContext
import AudioPlayerCore

public protocol InstantPageScrollableItem: AnyObject, InstantPageItem {
    var contentSize: CGSize { get }
    var horizontalInset: CGFloat { get }
    var isRTL: Bool { get }
    
    func textItemAtLocation(_ location: CGPoint) -> (InstantPageTextItem, CGPoint)?
}

public final class InstantPageScrollableContentView: View {
    public let item: InstantPageScrollableItem
    
    public init(item: InstantPageScrollableItem, additionalViews: [InstantPageView]) {
        self.item = item
        super.init()
        for case let view as NSView in additionalViews {
            self.addSubview(view)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        item.drawInTile(context: ctx)
    }

}




public final class InstantPageScrollableView: ScrollView, InstantPageView {
    public let item: InstantPageScrollableItem
    public let contentNode: InstantPageScrollableContentView
    public let containerView: View = View()

    
    public override var hasVerticalScroller: Bool {
        get {
            return false
        }
        set {
            super.hasVerticalScroller = newValue
        }
    }

    
    public override func scrollWheel(with event: NSEvent) {
        
        var scrollPoint = contentView.bounds.origin
        let isInverted: Bool = System.isScrollInverted
        
        if event.scrollingDeltaX != 0 {
            if !isInverted {
                scrollPoint.x += -event.scrollingDeltaX
            } else {
                scrollPoint.x -= event.scrollingDeltaX
            }
            
            scrollPoint.x = max(0, min(scrollPoint.x, (documentView!.frame.width) - contentSize.width))
            
            clipView.scroll(to: scrollPoint)
            
            
        } else {
            superview?.enclosingScrollView?.scrollWheel(with: event)
        }
    }
    
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
      //  clipView.scroll(to: NSMakePoint(0, 0))
    }
    
    
//    @objc var contentOffset: NSPoint {
//        get {
//            return NSZeroPoint
//        }
//    }
    
    public init(item: InstantPageScrollableItem, arguments: InstantPageItemArguments, additionalViews: [InstantPageView]) {
        self.item = item
        self.contentNode = InstantPageScrollableContentView(item: item, additionalViews: additionalViews)
        super.init(frame: NSZeroRect)
       // wantsLayer = true
        
        containerView.frame = CGRect(origin: CGPoint(x: 0, y: 0.0), size: NSMakeSize(item.contentSize.width + item.horizontalInset * 2, item.contentSize.height))
        containerView.backgroundColor = .clear
        self.contentNode.frame = CGRect(origin: CGPoint(x: item.horizontalInset, y: 0.0), size: item.contentSize)
        
        
        containerView.addSubview(contentNode)
        self.documentView = containerView
        
        if item.isRTL {
            self.contentView.scroll(to: CGPoint(x: containerView.frame.width - item.frame.width, y: 0.0))
           // self.contentOffset = CGPoint(x: self.contentSize.width - item.frame.width, y: 0.0)
        }
        
    }
    
    public override var needsDisplay: Bool {
        didSet {
            contentNode.needsDisplay = true
        }
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateIsVisible(_ isVisible: Bool) {
    }
    
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
    }
    
    
    public func updateHiddenMedia(media: InstantPageMedia?) {
    }
    

}
