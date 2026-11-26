import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import InAppSettings
import TelegramMediaResources
import ChatHistoryModel
import Localization
import TelegramContext
import TelegramMediaUtils
import TelegramTheme

public class ChatMapRowItem: ChatMediaItem {
    fileprivate var liveText: TextViewLayout?
    fileprivate var updatedText: TextViewLayout?
    public override init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        super.init(initialSize, chatInteraction, context, object, theme: theme)
        let map = media as! TelegramMediaMap
      //  let isVenue = map.venue != nil
        let resource =  MapSnapshotMediaResource(latitude: map.latitude, longitude: map.longitude, width: 320 * 2, height: 120 * 2, zoom: 15)
        //let resource = HttpReferenceMediaResource(url: "https://maps.googleapis.com/maps/api/staticmap?center=\(map.latitude),\(map.longitude)&zoom=15&size=\(isVenue ? 60 * Int(2.0) : 320 * Int(2.0))x\(isVenue ? 60 * Int(2.0) : 120 * Int(2.0))&sensor=true", size: 0)
        self.parameters = ChatMediaMapLayoutParameters(map: map, resource: resource, presentation: .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme), automaticDownload: downloadSettings.isDownloable(object.message!), execute: {
            
            ChatNavigationHooks.shared.showLocationPreview(context, map, object.message!.effectiveAuthor, object.message!.id, context.window)
        })
        
        if isLiveLocationView {
            liveText = TextViewLayout(.initialize(string: strings().chatLiveLocation, color: theme.chat.textColor(isIncoming, object.renderType == .bubble), font: .bold(.text)), maximumNumberOfLines: 1, truncationType: .end)
            
            var editedDate:Int32 = object.message!.timestamp
            for attr in object.message!.attributes {
                if let attr = attr as? EditedMessageAttribute {
                    editedDate = attr.date
                }
            }
                        
            var time:TimeInterval = Date().timeIntervalSince1970
            time += context.timeDifference
            let timeUpdated = Int32(time) - editedDate
                
            updatedText = TextViewLayout(.initialize(string: timeUpdated < 60 ? strings().chatLiveLocationUpdatedNow : strings().chatLiveLocationUpdatedOther(Int(timeUpdated / 60)), color: theme.chat.grayText(isIncoming, object.renderType == .bubble), font: .normal(.text)), maximumNumberOfLines: 1)
        }
    }
    
    public override var isForceRightLine: Bool {
        if let parameters = parameters as? ChatMediaMapLayoutParameters {
            if parameters.isVenue {
                if rightSize.width > (_contentSize.width - 70) {
                    return true
                }
            }
        }
        return super.isForceRightLine
    }
    
    
    public override var instantlyResize:Bool {
        if let parameters = parameters as? ChatMediaMapLayoutParameters {
            return parameters.isVenue
        }
        return false
    }
    
    public override var isBubbleFullFilled: Bool {
        if let media = media as? TelegramMediaMap {
            return media.venue == nil && isBubbled
        }
        return false
    }
    
    public var isLiveLocationView: Bool {
        if let media = media as? TelegramMediaMap, let message = message {
            if let liveBroadcastingTimeout = media.liveBroadcastingTimeout {
                if liveBroadcastingTimeout == .max {
                    return true
                } else {
                    var time:TimeInterval = Date().timeIntervalSince1970
                    time -= context.timeDifference
                    if Int(time) < Int(message.timestamp) + Int(liveBroadcastingTimeout) {
                        return true
                    }
                }
                
            }
        }
        return false
    }
    
    public var liveLocationTimeout: Int32 {
        if let media = media as? TelegramMediaMap {
            if let liveBroadcastingTimeout = media.liveBroadcastingTimeout {
                return liveBroadcastingTimeout
            }
        }
        return 0
    }
    
    public var liveLocationProgress: TimeInterval {
        if let media = media as? TelegramMediaMap {
            if let liveBroadcastingTimeout = media.liveBroadcastingTimeout, let message = message {
                var time:TimeInterval = Date().timeIntervalSince1970
                time -= context.timeDifference
                return 100.0 - (Double(time) - Double(message.timestamp)) / Double(liveBroadcastingTimeout) * 100.0
            }
        }
        return 0
    }
    
    public override func viewClass() -> AnyClass {
        return isLiveLocationView ? LiveLocationRowView.self : super.viewClass()
    }
    
    public override var isStateOverlayLayout: Bool {
        return !isLiveLocationView && hasBubble && isBubbleFullFilled
    }
    
    
    
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        if let parameters = parameters as? ChatMediaMapLayoutParameters {
            parameters.venueText?.measure(width: width - 70)
            var size:NSSize = parameters.defaultImageSize
            if !parameters.isVenue {
                size = parameters.defaultImageSize.aspectFitted(NSMakeSize(min(width,parameters.defaultImageSize.width), parameters.defaultImageSize.height))
                parameters.arguments = TransformImageArguments(corners: ImageCorners(radius: .cornerRadius), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets())
            }
            var venueSize: CGFloat = 0
            if let venueText = parameters.venueText {
                venueSize = venueText.layoutSize.width + 10
            }
        
            return NSMakeSize(venueSize + size.width, size.height)
        }
        return super.makeContentSize(width)
    }
    
    public override var height: CGFloat {
        if isLiveLocationView {
            liveText?.measure(width: _contentSize.width - elementsContentInset * 2)
            updatedText?.measure(width: _contentSize.width - elementsContentInset * 2)
            return super.height + (renderType == .bubble ? 46 : 40)
        }
        return super.height
    }
    
}

public class LiveLocationRowView : ChatMediaView {
    private let liveText: TextView = TextView()
    private let updatedText: TextView = TextView()
    private let progress:TimableProgressView = TimableProgressView(theme: TimableProgressTheme(seconds: 20))
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rowView.addSubview(updatedText)
        rowView.addSubview(liveText)
        rowView.addSubview(progress)
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        
        guard let item = item as? ChatMapRowItem else {return}
        
        liveText.update(item.liveText)
        updatedText.update(item.updatedText)
        
//        let difference:()->TimeInterval = {
//            return TimeInterval((countdownBeginTime + attribute.timeout)) - (CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
//        }
//        let start = difference() / Double(attribute.timeout) * 100.0
        if item.isLiveLocationView {
            progress.theme = TimableProgressTheme(backgroundColor: .clear, foregroundColor: theme.chat.textColor(item.isIncoming, item.entry.renderType == .bubble), seconds: Double(item.liveLocationTimeout), start: item.liveLocationProgress, borderWidth: 2)
            progress.progress = 0
            progress.isHidden = false
            rightView.isHidden = true
        } else {
            progress.isHidden = true
            rightView.isHidden = false
        }
        
        
        progress.startAnimation()
        super.set(item: item, animated: animated)

    }
    
    public override func updateColors() {
        super.updateColors()
        liveText.backgroundColor = contentColor
        updatedText.backgroundColor = contentColor
    }
    
    private func textFrame(_ item: ChatRowItem) -> NSRect {
        guard let item = item as? ChatMapRowItem else { return .zero }
        guard let liveText = item.liveText else {return NSZeroRect}
        let contentFrame = self.cachedContentFrame(item)
        return NSMakeRect(contentFrame.minX + item.elementsContentInset, contentFrame.maxY + item.defaultContentInnerInset, liveText.layoutSize.width, liveText.layoutSize.height)
    }
    private func updateFrame(_ item: ChatRowItem) -> NSRect {
        guard let item = item as? ChatMapRowItem else { return .zero }
        guard let updatedText = item.updatedText else {return NSZeroRect}
        let contentFrame = self.cachedContentFrame(item)
        return NSMakeRect(contentFrame.minX + item.elementsContentInset, contentFrame.maxY + item.defaultContentInnerInset + liveText.frame.height, updatedText.layoutSize.width, updatedText.layoutSize.height)
    }
    
    private func progressFrame(_ item: ChatRowItem) -> NSRect {
        let contentFrame = self.cachedContentFrame(item)
        return NSMakeRect(contentFrame.maxX - progress.frame.width - (item.isBubbled ? item.defaultContentInnerInset : 0) - 3, contentFrame.maxY + item.defaultContentInnerInset + 5, 25, 25)
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? ChatMapRowItem else { return }

        liveText.frame = textFrame(item)
        updatedText.frame = updateFrame(item)
        progress.frame = progressFrame(item)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
