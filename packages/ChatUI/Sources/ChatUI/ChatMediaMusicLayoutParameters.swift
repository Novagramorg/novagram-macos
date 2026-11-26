import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import AudioPlayerCore

public class ChatMediaMusicLayoutParameters : ChatMediaLayoutParameters {
    public let resource: TelegramMediaResource
    public let title:String?
    public let performer:String?
    public let isWebpage: Bool
    public let nameLayout:TextViewLayout
    public let showPlayer:(APController) -> Void
    public let durationLayout:TextViewLayout
    public let sizeLayout:TextViewLayout
    public init(nameLayout:TextViewLayout, durationLayout:TextViewLayout, sizeLayout:TextViewLayout, resource:TelegramMediaResource, isWebpage: Bool, title:String?, performer:String?, showPlayer:@escaping(APController) -> Void, presentation: ChatMediaPresentation, media: Media, automaticDownload: Bool) {
        self.nameLayout = nameLayout
        self.sizeLayout = sizeLayout
        self.durationLayout = durationLayout
        self.showPlayer = showPlayer
        self.isWebpage = isWebpage
        self.title = title
        self.performer = performer
        self.resource = resource
        super.init(presentation: presentation, media: media, automaticDownload: automaticDownload, autoplayMedia: AutoplayMediaPreferences.defaultSettings, isRevealed: nil)
    }
    
    public var file: TelegramMediaFile {
        return media as! TelegramMediaFile
    }
    
    public override func makeLabelsForWidth(_ width: CGFloat) -> CGFloat {
        nameLayout.measure(width: width - 50)
        durationLayout.measure(width: width - 50)
        sizeLayout.measure(width: width - 50)
        
        
        return max(nameLayout.layoutSize.width, durationLayout.layoutSize.width, sizeLayout.layoutSize.width) + 50
    }
}
