import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import InAppSettings
import TelegramMediaResources
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils

public final class ChatMediaMapLayoutParameters : ChatMediaLayoutParameters {
    public let map:TelegramMediaMap
    public let resource:TelegramMediaResource
    public let image:TelegramMediaImage
    public let venueText:TextViewLayout?
    public let isVenue:Bool
    public let defaultImageSize:NSSize
    public let url:String
    
    public let execute: ()->Void
    
    public var arguments:TransformImageArguments
    public init(map:TelegramMediaMap, resource:TelegramMediaResource, presentation: ChatMediaPresentation, automaticDownload: Bool, execute: @escaping() -> Void, imageSize: NSSize? = nil, cornerRadius: CGFloat = 8) {
        self.map = map
        self.isVenue = map.venue != nil
        self.resource = resource
        self.execute = execute
        self.defaultImageSize = imageSize ?? (isVenue ? NSMakeSize(60, 60) : NSMakeSize(320, 120))
        self.url = "https://maps.google.com/maps?q=\(String(format:"%f", map.latitude)),\(String(format:"%f", map.longitude))"
        let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(defaultImageSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
        
        self.image = TelegramMediaImage(imageId: map.id ?? MediaId(namespace: 0, id: arc4random64()), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        
        self.arguments = TransformImageArguments(corners: ImageCorners(radius: cornerRadius), imageSize: defaultImageSize, boundingSize: defaultImageSize, intrinsicInsets: NSEdgeInsets())
        if let venue = map.venue {
            let attr = NSMutableAttributedString()
            _ = attr.append(string: venue.title, color: presentation.text, font: .normal(.text))
            _ = attr.append(string: "\n")
            _ = attr.append(string: venue.address, color: presentation.grayText, font: .normal(.text))
            venueText = TextViewLayout(attr, maximumNumberOfLines: 4, truncationType: .middle, alignment: .left)
        } else {
            venueText = nil
        }
        super.init(presentation: presentation, media: map, automaticDownload: automaticDownload, autoplayMedia: AutoplayMediaPreferences.defaultSettings)
    }
}

public func ==(lhs:ChatMediaMapLayoutParameters, rhs:ChatMediaMapLayoutParameters) -> Bool {
    return lhs.resource.isEqual(to: rhs.resource)
}
