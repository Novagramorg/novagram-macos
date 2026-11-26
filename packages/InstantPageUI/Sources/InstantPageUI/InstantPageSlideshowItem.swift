import Cocoa
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import TelegramContext
import AudioPlayerCore
import TelegramCore
import SwiftSignalKit
import RangeSet

import TGUIKit

public class InstantPageSlideshowItem: InstantPageItem {
    public var frame: CGRect
    
    public let medias: [InstantPageMedia]
    public let wantsView: Bool = true
    public let hasLinks: Bool = false
    public let isInteractive: Bool = true
    public let separatesTiles: Bool = false

    public let webPage: TelegramMediaWebpage
    
    public init(frame: CGRect, webPage: TelegramMediaWebpage, medias: [InstantPageMedia]) {
        self.frame = frame
        self.webPage = webPage
        self.medias = medias
    }
    
    public func drawInTile(context: CGContext) {
        
    }
    
    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func matchesView(_ node: InstantPageView) -> Bool {
        if let view = node as? InstantPageSlideshowView {
            return self.medias == view.medias
        }
        return false
    }

    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return InstantPageSlideshowView(frameRect: frame, medias: medias, context: arguments.context)
    }
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public func distanceThresholdGroup() -> Int? {
        return 1
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        return 1000
    }

}

public class InstantPageSlideshowView : View, InstantPageView {
    fileprivate let medias: [InstantPageMedia]
    private let slideView: SliderView
    public init(frameRect: NSRect, medias: [InstantPageMedia], context: any AccountContextProtocol) {
        self.medias = medias
        slideView = SliderView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        super.init(frame: frameRect)
        addSubview(slideView)
        
        for media in medias {
            var arguments: InstantPageMediaArguments = .image(interactive: true, roundCorners: false, fit: false)
            if let media = media.media as? TelegramMediaFile {
                if media.isVideo {
                    arguments = .video(interactive: true, autoplay: media.isAnimated)
                }
            }
            let view = InstantPageMediaView(context: context, media: media, arguments: arguments)
            slideView.addSlide(view)
        }
        
    }
    
    public override func layout() {
        super.layout()
        slideView.center()
    }
    
    public var indexOfDisplayedSlide: Int {
        return Int(slideView.indexOfDisplayedSlide)
    }
    
    public override func copy() -> Any {
        
        return slideView.displayedSlide?.copy() ?? super.copy()
    }
    
    public func updateIsVisible(_ isVisible: Bool) {
        
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
