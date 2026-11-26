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


public final class InstantPagePeerReferenceItem: InstantPageItem {
   

    public let hasLinks: Bool = false
    public let isInteractive: Bool = false
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public var frame: CGRect
    public let wantsView: Bool = true
    public let separatesTiles: Bool = false
    public let medias: [InstantPageMedia] = []
    
    public let initialPeer: Peer
    public let safeInset: CGFloat
    public let transparent: Bool
    public let rtl: Bool
    
    public init(frame: CGRect, initialPeer: Peer, safeInset: CGFloat, transparent: Bool, rtl: Bool) {
        self.frame = frame
        self.initialPeer = initialPeer
        self.safeInset = safeInset
        self.transparent = transparent
        self.rtl = rtl
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return nil
    }
    
    public func matchesView(_ node: InstantPageView) -> Bool {
        return false
    }
    
    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func distanceThresholdGroup() -> Int? {
        return 5
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        if count > 3 {
            return 1000.0
        } else {
            return CGFloat.greatestFiniteMagnitude
        }
    }
    
    public func linkSelectionRects(at point: CGPoint) -> [CGRect] {
        return []
    }
    
    public func drawInTile(context: CGContext) {
    }
}
