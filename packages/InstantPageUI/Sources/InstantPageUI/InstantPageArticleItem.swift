import Cocoa
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import TelegramContext
import AudioPlayerCore
import Foundation
import Postbox
import TelegramCore

import TGUIKit
import SwiftSignalKit
import RangeSet


public final class InstantPageArticleItem: InstantPageItem {
    
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public let hasLinks: Bool = false
    
    
    public let isInteractive: Bool = false
    

    
    public var frame: CGRect
    public let wantsView: Bool = true
    public let separatesTiles: Bool = false
    public let medias: [InstantPageMedia] = []
    public let webPage: TelegramMediaWebpage
    
    public let contentItems: [InstantPageItem]
    public let contentSize: CGSize
    public let cover: TelegramMediaImage?
    public let url: String
    public let webpageId: MediaId
    public let rtl: Bool
    
    public init(frame: CGRect, webPage: TelegramMediaWebpage, contentItems: [InstantPageItem], contentSize: CGSize, cover: TelegramMediaImage?, url: String, webpageId: MediaId, rtl: Bool) {
        self.frame = frame
        self.webPage = webPage
        self.contentItems = contentItems
        self.contentSize = contentSize
        self.cover = cover
        self.url = url
        self.webpageId = webpageId
        self.rtl = rtl
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return InstantPageArticleView(context: arguments.context, item: self, webPage: self.webPage, contentItems: self.contentItems, contentSize: self.contentSize, cover: self.cover, url: self.url, webpageId: self.webpageId, rtl: self.rtl, openUrl: arguments.openUrl)
    }
    
    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func matchesView(_ view: InstantPageView) -> Bool {
        if let view = view as? InstantPageArticleView {
            return self === view.item
        } else {
            return false
        }
    }
    
    public func distanceThresholdGroup() -> Int? {
        return 7
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        if count > 3 {
            return 1000.0
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

public func layoutArticleItem(theme: InstantPageTheme, webPage: TelegramMediaWebpage, title: NSAttributedString, description: NSAttributedString, cover: TelegramMediaImage?, url: String, webpageId: MediaId, boundingWidth: CGFloat, rtl: Bool) -> InstantPageArticleItem {
    let inset: CGFloat = 17.0
    let imageSpacing: CGFloat = 10.0
    var sideInset = inset
    let imageSize = CGSize(width: 44.0, height: 44.0)
    if cover != nil {
        sideInset += imageSize.width + imageSpacing
    }
    
    var availableLines: Int = 3
    var contentHeight: CGFloat = 15.0 * 2.0
    
    var hasRTL = false
    var contentItems: [InstantPageItem] = []
    let (titleTextItem, titleItems, titleSize) = layoutTextItemWithString(title, boundingWidth: boundingWidth - inset - sideInset, offset: CGPoint(x: inset, y: 15.0), maxNumberOfLines: availableLines)
    contentItems.append(contentsOf: titleItems)
    contentHeight += titleSize.height
    
    if let textItem = titleTextItem {
        availableLines -= textItem.lines.count
        if textItem.containsRTL {
            hasRTL = true
        }
    }
    var descriptionInset = inset
    if hasRTL && cover != nil {
        descriptionInset += imageSize.width + imageSpacing
        for var item in titleItems {
            item.frame = item.frame.offsetBy(dx: imageSize.width + imageSpacing, dy: 0.0)
        }
    }
    
    if availableLines > 0 {
        let (descriptionTextItem, descriptionItems, descriptionSize) = layoutTextItemWithString(description, boundingWidth: boundingWidth - inset - sideInset, alignment: hasRTL ? .right : .natural, offset: CGPoint(x: descriptionInset, y: 15.0 + titleSize.height + 14.0), maxNumberOfLines: availableLines)
        contentItems.append(contentsOf: descriptionItems)
        
        if let textItem = descriptionTextItem {
            if textItem.containsRTL || hasRTL {
                hasRTL = true
            }
        }
        contentHeight += descriptionSize.height + 14.0
    }
    
    let contentSize = CGSize(width: boundingWidth, height: contentHeight)
    return InstantPageArticleItem(frame: CGRect(origin: CGPoint(), size: CGSize(width: boundingWidth, height: contentSize.height)), webPage: webPage, contentItems: contentItems, contentSize: contentSize, cover: cover, url: url, webpageId: webpageId, rtl: rtl || hasRTL)
}








public final class InstantPageArticleView: Button, InstantPageView {
    public let item: InstantPageArticleItem
    
    
    private let contentTile: InstantPageTile
    private let contentTileView: InstantPageTileView
    private var imageView: TransformImageView?
    
    public let url: String
    public let webpageId: MediaId
    public let cover: TelegramMediaImage?
    public let rtl: Bool
    
    private let openUrl: (InstantPageUrlItem) -> Void
    
    private var fetchedDisposable = MetaDisposable()
    
    public init(context: any AccountContextProtocol, item: InstantPageArticleItem, webPage: TelegramMediaWebpage, contentItems: [InstantPageItem], contentSize: CGSize, cover: TelegramMediaImage?, url: String, webpageId: MediaId, rtl: Bool, openUrl: @escaping (InstantPageUrlItem) -> Void) {
        self.item = item
        self.url = url
        self.webpageId = webpageId
        self.cover = cover
        self.rtl = rtl
        self.openUrl = openUrl
        
        self.contentTile = InstantPageTile(frame: CGRect(x: 0.0, y: 0.0, width: contentSize.width, height: contentSize.height))
        self.contentTile.items.append(contentsOf: contentItems)
        self.contentTileView = InstantPageTileView(tile: self.contentTile, backgroundColor: .clear)
        
        super.init()
        
        self.addSubview(self.contentTileView)
        
        if let image = cover {
            let imageView = TransformImageView()
            
            let imageReference = ImageMediaReference.webPage(webPage: WebpageReference(webPage), media: image)
            imageView.setSignal(chatMessagePhoto(account: context.account, imageReference: imageReference, scale: backingScaleFactor))
            self.fetchedDisposable.set(chatMessagePhotoInteractiveFetched(account: context.account, imageReference: imageReference).start())
            
            self.imageView = imageView
            self.addSubview(imageView)
        }

        set(handler: { [weak self] _ in
            self?.click()
        }, for: .Up)
        
        set(background: theme.colors.grayBackground, for: .Highlight)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    deinit {
        self.fetchedDisposable.dispose()
    }
    
    private func click() {
        self.openUrl(InstantPageUrlItem(url: self.url, webpageId: self.webpageId))
    }
    
    public override func layout() {
        super.layout()
        
        let size = self.bounds.size
        let inset: CGFloat = 17.0
        let imageSize = CGSize(width: 44.0, height: 44.0)
        
        self.contentTileView.frame = self.bounds
        
        if let imageView = self.imageView, let image = self.cover, let largest = largestImageRepresentation(image.representations) {
            let size = largest.dimensions.size.aspectFilled(imageSize)
            let boundingSize = imageSize
            
            imageView.set(arguments: TransformImageArguments(corners: ImageCorners(radius: 5.0), imageSize: size, boundingSize: boundingSize, intrinsicInsets: NSEdgeInsets()))
        }
        
        if let imageView = self.imageView {
            if self.rtl {
                imageView.frame = CGRect(origin: CGPoint(x: inset, y: 11.0), size: imageSize)
            } else {
                imageView.frame = CGRect(origin: CGPoint(x: size.width - inset - imageSize.width, y: 11.0), size: imageSize)
            }
        }
    }
    
    public func updateIsVisible(_ isVisible: Bool) {
    }
    
    public override func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
    }
    

    
    public func updateHiddenMedia(media: InstantPageMedia?) {
    }
    
}
