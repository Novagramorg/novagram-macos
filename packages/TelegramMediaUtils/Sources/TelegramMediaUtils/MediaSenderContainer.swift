import Foundation
import Postbox
import TelegramCore
import TelegramMedia
import TelegramTheme

open class MediaSenderContainer : Equatable {
    public let path:String
    public let caption:String
    public let isFile:Bool
    public let isOneTime: Bool
    public init(path:String, caption:String = "", isFile:Bool = false, isOneTime: Bool = false) {
        self.path = path
        self.caption = caption
        self.isFile = isFile
        self.isOneTime = isOneTime
    }
    
    public static func ==(lhs: MediaSenderContainer, rhs: MediaSenderContainer) -> Bool {
        return lhs.path == rhs.path && lhs.caption == rhs.caption && lhs.isFile == rhs.isFile && lhs.isOneTime == rhs.isOneTime
    }
}

public func resolvedMIMEType(for container: MediaSenderContainer) -> String {
    let mimeType = MIMEType(container.path)
    if container.isFile && mimeType == "application/x-tgsticker" {
        return "application/binary"
    }
    return mimeType
}

open class ArchiverSenderContainer : MediaSenderContainer {
    public let files: [URL]
    public init(path:String, caption:String = "", isFile:Bool = true, files: [URL] = []) {
        self.files = files
        super.init(path: path, caption: caption, isFile: isFile, isOneTime: false)
    }
    
    public static func ==(lhs: ArchiverSenderContainer, rhs: ArchiverSenderContainer) -> Bool {
        return lhs.path == rhs.path && lhs.caption == rhs.caption && lhs.isFile == rhs.isFile && lhs.files == rhs.files
    }
}


open class VoiceSenderContainer : MediaSenderContainer {
    public let data:RecordedAudioData
    public let id:Int64?
    public init(data:RecordedAudioData, id: Int64?, isOneTime: Bool) {
        self.data = data
        self.id = id
        let path: String = data.path
        super.init(path: path, isOneTime: isOneTime)
        
    }
}

open class VideoMessageSenderContainer : MediaSenderContainer {
    public let duration:Int
    public let size: CGSize
    public let id:Int64?
    public init(path:String, duration: Int, size: CGSize, id: Int64?, isOneTime: Bool) {
        self.duration = duration
        self.size = size
        self.id = id
        super.init(path: path, caption: "", isFile: false, isOneTime: isOneTime)
    }
}