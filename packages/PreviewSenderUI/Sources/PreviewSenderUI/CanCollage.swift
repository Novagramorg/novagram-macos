import Foundation
import Cocoa
import TelegramCore
import TelegramTheme
import TelegramMediaUtils

public func canCollagesFromUrl(_ urls:[URL]) -> Bool {
    let canCollage: Bool = urls.count >= 1
    
    var musicCount: Int = 0
    var voiceCount: Int = 0
    var gifCount: Int = 0
    if canCollage {
        for url in urls {
            let mime = MIMEType(url.path)
            let attrs = mime.hasPrefix("audio/") || mime.hasPrefix("video") ? CollageHooks.shared.fileAttributes(mime, url.path, true, true) : []
            let isGif = attrs.contains(where: { attr -> Bool in
                switch attr {
                case .Animated:
                    return true
                default:
                    return false
                }
            })
            let isMusic = attrs.contains(where: { attr -> Bool in
                switch attr {
                case let .Audio(isVoice, _, _, _, _):
                    return !isVoice
                default:
                    return false
                }
            })
            let isVoice = attrs.contains(where: { attr -> Bool in
                switch attr {
                case let .Audio(isVoice, _, _, _, _):
                    return isVoice
                default:
                    return false
                }
            })
            if mime == "image/webp" {
                return false
            }
            if isMusic {
                musicCount += 1
            }
            if isVoice {
                voiceCount += 1
            }
            if isGif {
                gifCount += 1
            }
        }
    }
    
    if musicCount > 0 {
        if musicCount == urls.count {
            return true
        } else {
            return false
        }
    }
    if voiceCount > 0 {
        return false
    }
    if gifCount > 0 {
        return false
    }
    return canCollage
}
