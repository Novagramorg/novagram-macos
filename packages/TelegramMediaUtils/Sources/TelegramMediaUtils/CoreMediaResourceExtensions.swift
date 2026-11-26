import Foundation
import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import TelegramTheme
import TelegramMediaResources

public extension TelegramMediaFile {
    var elapsedSize: Int64 {
        if let size = size {
            return size
        }
        if let resource = resource as? LocalFileReferenceMediaResource, let size = resource.size {
            return Int64(size)
        }
        return 0
    }
}

public extension Media {
    
    
    var canHaveCaption: Bool {
        if supposeToBeSticker {
            return false
        }
        if self is TelegramMediaImage {
            return true
        } else if let file = self as? TelegramMediaFile {
            if file.isInstantVideo || file.isAnimatedSticker || file.isStaticSticker || file.isVoice {
                return false
            } else {
                return true
            }
        }
        return false
    }
}

public extension Media {
    var isGraphicFile:Bool {
        if let media = self as? TelegramMediaFile {
            return media.mimeType.hasPrefix("image") && (media.mimeType.contains("png") || media.mimeType.contains("jpg") || media.mimeType.contains("jpeg") || media.mimeType.contains("tiff") || media.mimeType.contains("heic"))
        }
        return false
    }
    
    var probablySticker: Bool {
        guard let file = self as? TelegramMediaFile else {
            return false
        }
        if file.isAnimatedSticker {
            return true
        }
        if file.isStaticSticker {
            return true
        }
        if file.isVideoSticker {
            return true
        }
        if file.mimeType == "image/webp" {
            return true
        }
        return false
    }
    
    var isVideoFile:Bool {
        if let media = self as? TelegramMediaFile {
            return media.mimeType.hasPrefix("video/mp4") || media.mimeType.hasPrefix("video/mov") || media.mimeType.hasPrefix("video/avi")
        }
        return false
    }
    var hasNoSound: Bool {
        if let media = self as? TelegramMediaFile {
            for attr in media.attributes {
                switch attr {
                case let .Video(_, _, flags, _, _, _):
                    return flags.contains(.isSilent)
                default:
                    return false
                }
            }
        }
        return false
    }
    
    var supposeToBeSticker:Bool {
        if let media = self as? TelegramMediaFile {
            if media.mimeType.hasPrefix("image/webp") {
                return true
            }
        }
        return false
    }
}

public func mediaResource(from media:Media?) -> TelegramMediaResource? {
    if let media = media as? TelegramMediaFile {
        return media.resource
    } else if let media = media as? TelegramMediaImage {
        return largestImageRepresentation(media.representations)?.resource
    }
    return nil
}

public func mediaResourceMIMEType(from media:Media?) -> String? {
    if let media = media as? TelegramMediaFile {
        return media.mimeType
    } else if media is TelegramMediaImage {
        return "image/jpeg"
    }
    return nil
}

public func mediaResourceName(from media:Media?, ext:String?) -> String {
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let ext = ext ?? ".file"
    if let media = media as? TelegramMediaFile {
        return media.fileName ?? "FILE " + dateFormatter.string(from: Date()) + "." + ext
    } else if media is TelegramMediaImage {
        return "IMAGE " + dateFormatter.string(from: Date())  + "." + ext
    }
    return "FILE " + dateFormatter.string(from: Date())  + "." + ext
}

public func fileExtenstion(_ file: TelegramMediaFile) -> String {
    return fileExt(file.mimeType) ?? file.fileName?.nsstring.pathExtension ?? ""
}

public extension TelegramMediaImage {
    var isLocalResource: Bool {
        if let resource = representations.last?.resource {
            if resource is LocalFileMediaResource {
                return true
            }
            if resource is LocalFileReferenceMediaResource {
                return true
            }
        }
        return false
    }
}

public extension TelegramMediaFile {
    var isLocalResource: Bool {
        if resource is LocalFileMediaResource {
            return true
        }
        if resource is LocalFileReferenceMediaResource {
            return true
        }
        return false
    }

}

public extension TelegramMediaImage {
    convenience init(dimension: PixelDimensions, immediateThumbnailData: Data?) {
        self.init(imageId: .init(namespace: 0, id: 0), representations: [.init(dimensions: dimension, resource: LocalBundleResource(name: "", ext: ""), progressiveSizes: [], immediateThumbnailData: immediateThumbnailData)], immediateThumbnailData: immediateThumbnailData, reference: nil, partialReference: nil, flags: [])

    }
}
