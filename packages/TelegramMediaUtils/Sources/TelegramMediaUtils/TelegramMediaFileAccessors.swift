import Cocoa
import TelegramCore
import Postbox
import TGUIKit

public extension TelegramMediaFile {
    var videoSize:NSSize {
        for attr in attributes {
            if case let .Video(_,size, _, _, _, _) = attr {
                return size.size
            }
        }
        return NSZeroSize
    }
    
    var isStreamable: Bool {
        for attr in attributes {
            if case let .Video(_, _, flags, _, _, _) = attr {
                return flags.contains(.supportsStreaming)
            }
        }
        return true
    }
    
//    var streaming: MediaPlayerStreaming {
//        for attr in attributes {
//            if case let .Video(_, _, flags) = attr {
//                if flags.contains(.supportsStreaming) {
//                    return .earlierStart
//                } else {
//                    return .none
//                }
//            }
//        }
//        return .none
//    }
    
    
    var imageSize:NSSize {
        for attr in attributes {
            if case let .ImageSize(size) = attr {
                return size.size
            }
        }
        return NSZeroSize
    }
    
    var videoDuration: Double {
        for attr in attributes {
            if case let .Video(duration,_, _, _, _, _) = attr {
                return duration
            }
        }
        return 0
    }
    
    var isTheme: Bool {
        return mimeType == "application/x-tgtheme-macos"
    }
    
    
}
