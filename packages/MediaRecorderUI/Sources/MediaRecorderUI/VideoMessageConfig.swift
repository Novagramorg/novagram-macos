import Foundation
import TelegramCore
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif



public struct VideoMessageConfig : Equatable {
    public static var defaultValue: VideoMessageConfig {
        return VideoMessageConfig(videoBitrate: 1000, audioBitrate: 64, diameter: 384, fileSizeLimit: 12 * 1024 * 1024)
    }
    
    public let videoBitrate: Int
    public let audioBitrate: Int
    public let fileSizeLimit: Int
    public let diameter: Int
    fileprivate init(videoBitrate: Int, audioBitrate: Int, diameter: Int, fileSizeLimit: Int) {
        self.videoBitrate = videoBitrate
        self.audioBitrate = audioBitrate
        self.fileSizeLimit = fileSizeLimit
        self.diameter = diameter
    }
    
    public static func with(appConfiguration: AppConfiguration) -> VideoMessageConfig {
        if let data = appConfiguration.data, let video = data["round_video_encoding"] as? [String:Any] {
            let d = VideoMessageConfig.defaultValue
            let videoBitrate = video["video_bitrate"] as? Double ?? Double(d.videoBitrate)
            let audioBitrate = video["audio_bitrate"] as? Double ?? Double(d.audioBitrate)
            let maxSize = video["max_size"] as? Double ?? Double(d.fileSizeLimit)
            let diameter = video["diameter"] as? Double ?? Double(d.diameter)
            return .init(videoBitrate: Int(videoBitrate), audioBitrate: Int(audioBitrate), diameter: Int(diameter), fileSizeLimit: Int(maxSize))
        } else {
            return .defaultValue
        }
    }

}
