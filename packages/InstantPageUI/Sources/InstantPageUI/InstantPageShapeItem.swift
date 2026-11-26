import Cocoa
import TGUIKit
import TelegramContext
import AudioPlayerCore
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme

import TelegramCore
import SwiftSignalKit
import RangeSet


public enum InstantPageShape {
    case rect
    case ellipse
    case roundLine
}

public final class InstantPageShapeItem: InstantPageItem {
    public var frame: CGRect
    public let shapeFrame: CGRect
    public let shape: InstantPageShape
    public let color: NSColor
    
    public let medias: [InstantPageMedia] = []
    public let wantsView: Bool = false
    public let hasLinks: Bool = false
    public let separatesTiles: Bool = false

    public let isInteractive: Bool = false
    
    public init(frame: CGRect, shapeFrame: CGRect, shape: InstantPageShape, color: NSColor) {
        self.frame = frame
        self.shapeFrame = shapeFrame
        self.shape = shape
        self.color = color
    }
    
    public func drawInTile(context: CGContext) {
        context.setFillColor(self.color.cgColor)
        
        switch self.shape {
        case .rect:
            context.fill(self.shapeFrame.offsetBy(dx: self.frame.minX, dy: self.frame.minY))
        case .ellipse:
            context.fillEllipse(in: self.shapeFrame.offsetBy(dx: self.frame.minX, dy: self.frame.minY))
        case .roundLine:
            if self.shapeFrame.size.width < self.shapeFrame.size.height {
                let radius = self.shapeFrame.size.width / 2.0
                var shapeFrame = self.shapeFrame.offsetBy(dx: self.frame.minX, dy: self.frame.minY)
                shapeFrame.origin.y += radius
                shapeFrame.size.height -= radius + radius
                context.fill(shapeFrame)
                context.fillEllipse(in: CGRect(x: shapeFrame.minX, y: shapeFrame.minY - radius, width: radius + radius, height: radius + radius))
                context.fillEllipse(in: CGRect(x: shapeFrame.minX, y: shapeFrame.maxY - radius, width: radius + radius, height: radius + radius))
            } else {
                context.fill(self.shapeFrame.offsetBy(dx: self.frame.minX, dy: self.frame.minY))
            }
        }
    }
    
    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func matchesView(_ node: InstantPageView) -> Bool {
        return false
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return nil
    }
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public func distanceThresholdGroup() -> Int? {
        return nil
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        return 0.0
    }
}
