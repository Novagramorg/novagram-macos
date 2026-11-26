import Cocoa
import AVFoundation
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

open class CallAudioPlayer : NSObject, AVAudioPlayerDelegate {
    
    private var player: AVAudioPlayer?;
    open var completion:(()->Void)?
    
    public let tone: URL
    
    public init(_ url:URL, loops:Int, completion:(()->Void)? = nil) {
        self.tone = url
        self.player = try? AVAudioPlayer(contentsOf: url)
        self.completion = completion
        super.init()
        
        player?.numberOfLoops = loops
        player?.delegate = self
    }
    
    open func play() {
        player?.play()
    }
    open func stop() {
        player?.stop()
        player?.delegate = nil
        player = nil
    }
    deinit {
        stop()
    }
    
    open func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.completion?()
        player.delegate = nil
    }
    
}
