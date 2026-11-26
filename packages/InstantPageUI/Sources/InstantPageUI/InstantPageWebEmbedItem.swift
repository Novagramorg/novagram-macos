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


public final class InstantPageWebEmbedItem: InstantPageItem {
    public var frame: CGRect
    public let hasLinks: Bool = false
    public let wantsView: Bool = true
    public let medias: [InstantPageMedia] = []
    
    public let url: String?
    public let html: String?
    public let enableScrolling: Bool
    public let separatesTiles: Bool = false

    public let isInteractive: Bool = false
    
    public init(frame: CGRect, url: String?, html: String?, enableScrolling: Bool) {
        self.frame = frame
        self.url = url
        self.html = html
        self.enableScrolling = enableScrolling
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return InstantPageWebEmbedView(frame: self.frame, url: self.url, html: self.html, enableScrolling: self.enableScrolling, updateWebEmbedHeight: { height in
            arguments.updateWebEmbedHeight(height)

        })
    }
    
    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func matchesView(_ node: InstantPageView) -> Bool {
        if let node = node as? InstantPageWebEmbedView {
            return self.url == node.url && self.html == node.html
        } else {
            return false
        }
    }
    
    public func distanceThresholdGroup() -> Int? {
        return 3
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        if count > 3 {
            return 1000.0
        } else {
            return CGFloat.greatestFiniteMagnitude
        }
    }
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public func drawInTile(context: CGContext) {
    }
}
