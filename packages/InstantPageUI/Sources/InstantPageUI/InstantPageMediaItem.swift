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


public enum InstantPageMediaArguments {
    case image(interactive: Bool, roundCorners: Bool, fit: Bool)
    case video(interactive: Bool, autoplay: Bool)
    case map(InstantPageMapAttribute)
    public var isInteractive: Bool {
        switch self {
        case .image(let interactive, _, _):
            return interactive
        case .video(let interactive, _):
            return interactive
        case .map:
            return false
        }
    }
}

public final class InstantPageMediaItem: InstantPageItem {
    public var frame: CGRect
    
    public let media: InstantPageMedia
    public var medias: [InstantPageMedia] {
        return [self.media]
    }
    
    public var isInteractive: Bool {
        return arguments.isInteractive
    }
    
    public let arguments: InstantPageMediaArguments
    
    public let wantsView: Bool = true
    public let hasLinks: Bool = false
    public let separatesTiles: Bool = false

    public init(frame: CGRect, media: InstantPageMedia, arguments: InstantPageMediaArguments) {
        self.frame = frame
        self.media = media
        self.arguments = arguments
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return InstantPageMediaView(context: arguments.context, media: self.media, arguments: self.arguments)
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
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
}
