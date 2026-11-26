import Foundation
import TelegramCore
import Postbox
import Localization
import TGUIKit

public extension TelegramMediaFile {
    var customEmojiText:String? {
        for attr in attributes {
            if case let .CustomEmoji(_, _, alt, _) = attr {
                return alt
            }
        }
        return nil
    }
    
    var maskData: StickerMaskCoords? {
        for attr in attributes {
            if case let .Sticker(_, _, mask) = attr {
                return mask
            }
        }
        return nil
    }
    
    
    
    
    
    var musicText:(String,String) {
        
        var audioTitle:String?
        var audioPerformer:String?
        
        let file = self
        for attribute in file.attributes {
            if case let .Audio(_, _, title, performer, _) = attribute {
                audioTitle = title
                audioPerformer = performer
                break
            }
        }
        
        if let audioTitle = audioTitle, let audioPerformer = audioPerformer {
            if audioTitle.isEmpty && audioPerformer.isEmpty {
                return (file.fileName ?? "", "")
            } else {
                return (audioTitle, audioPerformer)
            }
        } else {
            return (file.fileName ?? "", "")
        }

    }
}
