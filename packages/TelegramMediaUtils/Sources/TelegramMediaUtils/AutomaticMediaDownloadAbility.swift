import Foundation
import TelegramCore
import Postbox
import TGUIKit
import TelegramTheme
import InAppSettings

public extension AutomaticMediaDownloadSettings {
    
    func isDownloable(_ message: Message, index: Int? = nil) -> Bool {
        
        if !automaticDownload {
            return false
        }
        
        
        func ability(_ category: AutomaticMediaDownloadCategoryPeers, _ peer: Peer) -> Bool {
            if peer.isGroup || peer.isSupergroup {
                return category.groupChats
            } else if peer.isChannel {
                return category.channels
            } else {
                return category.privateChats
            }
        }
        
        func checkFile(_ media: TelegramMediaFile, _ peer: Peer, _ categories: AutomaticMediaDownloadCategories) -> Bool {
            let size = Int64(media.size ?? 0)
            
            let dangerExts = "action app bin command csh osx workflow terminal url caction mpkg pkg xhtm webarchive"
            
            if let ext = media.fileName?.nsstring.pathExtension.lowercased(), dangerExts.components(separatedBy: " ").contains(ext) {
                return false
            }
            
            switch true {
            case media.isInstantVideo:
                return ability(categories.video, peer) && size <= (categories.video.fileSize ?? INT32_MAX)
            case media.isVideo && media.isAnimated:
                return ability(categories.video, peer) && size <= (categories.video.fileSize ?? INT32_MAX)
            case media.isVideo:
                return ability(categories.video, peer) && size <= (categories.video.fileSize ?? INT32_MAX)
            case media.isVoice:
                return size <= 1 * 1024 * 1024
            default:
                return ability(categories.files, peer) && size <= (categories.files.fileSize ?? INT32_MAX)
            }
        }
        
        if let peer = coreMessageMainPeer(message) {
            if let _ = message.anyMedia as? TelegramMediaImage {
                return ability(categories.photo, peer)
            } else if let media = message.anyMedia as? TelegramMediaFile {
                return checkFile(media, peer, categories)
            } else if let media = message.anyMedia as? TelegramMediaWebpage {
                switch media.content {
                case let .Loaded(content):
                    if content.type == "telegram_background" {
                         return ability(categories.photo, peer)
                    }
                    if let file = content.file {
                        return checkFile(file, peer, categories)
                    } else if let _ = content.image {
                        return ability(categories.photo, peer)
                    }
                default:
                    break
                }
            } else if let media = message.anyMedia as? TelegramMediaGame {
                if let file = media.file {
                    return checkFile(file, peer, categories)
                } else if let _ = media.image {
                    return ability(categories.photo, peer)
                }
            } else if let media = message.anyMedia as? TelegramMediaPaidContent, let index = index {
                switch media.extendedMedia[index] {
                case let .full(media):
                    if let file = media as? TelegramMediaFile {
                        return checkFile(file, peer, categories)
                    } else if let _ = media as? TelegramMediaImage {
                        return ability(categories.photo, peer)
                    }
                default:
                    return false
                }
                
            }
        }
        
        return false
    }
}
