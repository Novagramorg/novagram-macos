import Cocoa
import TGUIKit
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import TelegramContext
import AudioPlayerCore
import TelegramCore
import SwiftSignalKit
import RangeSet

import Postbox


public final class InstantPageItemArguments {
    public let context: any AccountContextProtocol
    public let theme: InstantPageTheme
    public let openMedia:(InstantPageMedia)->Void
    public let openPeer:(PeerId) -> Void
    public let openUrl:(InstantPageUrlItem) -> Void
    public let updateWebEmbedHeight:(CGFloat) -> Void
    public let updateDetailsExpanded: (Bool) -> Void
    public let isExpandedItem: (InstantPageDetailsItem) -> Bool
    public let effectiveRectForItem: (InstantPageItem) -> NSRect
    public init(context: any AccountContextProtocol, theme: InstantPageTheme, openMedia: @escaping (InstantPageMedia) -> Void, openPeer: @escaping (PeerId) -> Void, openUrl: @escaping (InstantPageUrlItem) -> Void, updateWebEmbedHeight: @escaping (CGFloat) -> Void, updateDetailsExpanded: @escaping (Bool) -> Void, isExpandedItem: @escaping(InstantPageDetailsItem) -> Bool, effectiveRectForItem: @escaping(InstantPageItem) -> NSRect) {
        self.context = context
        self.theme = theme
        self.openMedia = openMedia
        self.openPeer = openPeer
        self.openUrl = openUrl
        self.updateWebEmbedHeight = updateWebEmbedHeight
        self.updateDetailsExpanded = updateDetailsExpanded
        self.isExpandedItem = isExpandedItem
        self.effectiveRectForItem = effectiveRectForItem
    }
}

public protocol InstantPageItem {
    var frame: CGRect { get set }
    var hasLinks: Bool { get }
    var wantsView: Bool { get }
    var medias: [InstantPageMedia] { get }
    var separatesTiles: Bool { get }

    var isInteractive: Bool { get }
    
    func matchesAnchor(_ anchor: String) -> Bool
    func drawInTile(context: CGContext)
    func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)?
    func matchesView(_ node: InstantPageView) -> Bool
    func linkSelectionViews() -> [InstantPageLinkSelectionView]
    
    func distanceThresholdGroup() -> Int?
    func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat
}

