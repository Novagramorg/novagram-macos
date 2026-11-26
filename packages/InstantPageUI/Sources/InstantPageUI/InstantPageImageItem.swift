import Cocoa
import TGUIKit
import TelegramContext
import AudioPlayerCore
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import Postbox
import TelegramCore
import SwiftSignalKit
import RangeSet


public protocol InstantPageImageAttribute {
}

public struct InstantPageMapAttribute: InstantPageImageAttribute {
    public let zoom: Int32
    public let dimensions: CGSize
    public init(zoom: Int32, dimensions: CGSize) {
        self.zoom = zoom
        self.dimensions = dimensions
    }
}

public final class InstantPageImageItem: InstantPageItem {
    public let hasLinks: Bool = false
    public let isInteractive: Bool
    public let separatesTiles: Bool = false

    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public var frame: CGRect
    
    public let webPage: TelegramMediaWebpage
    
    public let media: InstantPageMedia
    public let attributes: [InstantPageImageAttribute]
    
    public var medias: [InstantPageMedia] {
        return [self.media]
    }
    
    public let roundCorners: Bool
    public let fit: Bool
    
    public let wantsView: Bool = true
    
    public init(frame: CGRect, webPage: TelegramMediaWebpage, media: InstantPageMedia, attributes: [InstantPageImageAttribute] = [], interactive: Bool, roundCorners: Bool, fit: Bool) {
        self.frame = frame
        self.webPage = webPage
        self.media = media
        self.isInteractive = interactive
        self.attributes = attributes
        self.roundCorners = roundCorners
        self.fit = fit
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        
        let viewArguments: InstantPageMediaArguments
        if let _ = media.media as? TelegramMediaMap, let attribute = attributes.first as? InstantPageMapAttribute {
            viewArguments = .map(attribute)
        } else {
            viewArguments = .image(interactive: self.isInteractive, roundCorners: self.roundCorners, fit: self.fit)
        }
        
        return  InstantPageMediaView(context: arguments.context, media: media, arguments: viewArguments)
    }
    
    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func matchesView(_ node: InstantPageView) -> Bool {
        if let node = node as? InstantPageMediaView {
            return node.media == self.media
        } else {
            return false
        }
    }
    
    public func distanceThresholdGroup() -> Int? {
        return 1
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        if count > 3 {
            return 400.0
        } else {
            return CGFloat.greatestFiniteMagnitude
        }
    }
    
    public func drawInTile(context: CGContext) {
    }
    
    public func linkSelectionRects(at point: CGPoint) -> [CGRect] {
        return []
    }
}




