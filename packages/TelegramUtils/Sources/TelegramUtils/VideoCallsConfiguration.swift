import TelegramCore
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public struct VideoCallsConfiguration: Equatable {
    public enum VideoCallsSupport {
        case disabled
        case full
        case onlyVideo
    }
    
    public var videoCallsSupport: VideoCallsSupport
    
    public init(appConfiguration: AppConfiguration) {
        var videoCallsSupport: VideoCallsSupport = .full
        if let data = appConfiguration.data, let value = data["video_calls_support"] as? String {
            switch value {
            case "disabled":
                videoCallsSupport = .disabled
            case "full":
                videoCallsSupport = .full
            case "only_video":
                videoCallsSupport = .onlyVideo
            default:
                videoCallsSupport = .full
            }
        }
        self.videoCallsSupport = videoCallsSupport
    }
}
