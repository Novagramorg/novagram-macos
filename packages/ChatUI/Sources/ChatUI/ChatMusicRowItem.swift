import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import ChatHistoryModel
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
public class ChatMusicRowItem: ChatMediaItem {
    
    
    public override init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        super.init(initialSize, chatInteraction, context, object, theme: theme)
        

        self.parameters = ChatMediaLayoutParameters.layout(for: (self.media as! TelegramMediaFile), isWebpage: chatInteraction.isLogInteraction, chatInteraction: chatInteraction, presentation: .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme), automaticDownload: downloadSettings.isDownloable(object.message!), isIncoming: object.message!.isIncoming(context.account, object.renderType == .bubble), autoplayMedia: object.autoplayMedia)
    }
    
    public override var isForceRightLine: Bool {
        if let parameters = parameters as? ChatMediaMusicLayoutParameters {
            if parameters.durationLayout.layoutSize.width + 50 + rightSize.width + insetBetweenContentAndDate > contentSize.width {
                return true
            }
        }
        return super.isForceRightLine
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        if let parameters = parameters as? ChatMediaMusicLayoutParameters {
            
            let width = min(320, width - 80)
            
            for layout in captionLayouts {
                layout.layout.measure(width: width)
            }
            let captionsWidth = captionLayouts.max(by: { $0.layout.size.width < $1.layout.size.width }).map { $0.layout.size.width }
            
            let labelsWidth = parameters.makeLabelsForWidth(width)
            return NSMakeSize(max(captionsWidth ?? 0, labelsWidth) + 50, 40)
        }
        return NSZeroSize
    }
}
