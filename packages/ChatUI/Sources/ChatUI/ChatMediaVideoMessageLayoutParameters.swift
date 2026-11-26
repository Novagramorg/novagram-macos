import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
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

public class ChatMediaVideoMessageLayoutParameters : ChatMediaLayoutParameters {
    public let isWebpage: Bool
    public let resource: TelegramMediaResource
    public let showPlayer:(APController) -> Void
    public let isMarked:Bool
    public let duration: Double
    public let durationLayout:TextViewLayout
    
    public var transcribe:()->Void = {}
    public var transcribeData: ChatMediaVoiceLayoutParameters.TranscribeData?
    
    public init(showPlayer:@escaping(APController) -> Void, duration: Double, isMarked:Bool, isWebpage: Bool, resource: TelegramMediaResource, presentation: ChatMediaPresentation, media: Media, automaticDownload: Bool, autoplayMedia: AutoplayMediaPreferences, isRevealed: Bool?) {
        self.showPlayer = showPlayer
        self.duration = duration
        self.isMarked = isMarked
        self.isWebpage = isWebpage
        self.resource = resource
        self.durationLayout = TextViewLayout(NSAttributedString.initialize(string: String.durationTransformed(elapsed: duration), color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1, truncationType:.end, alignment: .left)
        super.init(presentation: presentation, media: media, automaticDownload: automaticDownload, autoplayMedia: autoplayMedia, isRevealed: isRevealed)
    }
    
    public func duration(for duration:TimeInterval) -> TextViewLayout {
        return TextViewLayout(NSAttributedString.initialize(string: String.durationTransformed(elapsed: Int(duration)), color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1, truncationType:.end, alignment: .left)
    }
}
