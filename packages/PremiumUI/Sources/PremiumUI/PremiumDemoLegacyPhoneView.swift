import Cocoa
import Foundation
import TGUIKit
import TelegramMedia
import AVFoundation
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import CurrencyFormat
import SceneEffects
import InAppPurchaseManager
import InlineStickers
import ObjcUtils

public final class PremiumDemoLegacyPhoneView : View {
    private let phoneView = ImageView()
    private let videoView = MediaPlayerView()
    private var player: MediaPlayer?
    
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        phoneView.image = TelegramThemeHooks.shared.image(.iconPremiumIphone).precomposed()
        addSubview(videoView)
        videoView.cornerRadius = 0
        addSubview(phoneView)
        phoneView.isAccessibilityDecorative = true
        phoneView.sizeToFit()
    }
    
    public enum Position {
        case top
        case bottom
    }
    
    private var position: Position = .top
    
    public var status: Signal<MediaPlayerStatus, NoError>?
    
    public func setup(context: (any AccountContextProtocol), video: TelegramMediaFile?, position: Position) {
        self.position = position
        if let video = video {
                                    
            let mediaPlayer = MediaPlayer(postbox: context.account.postbox, userLocation: .other, userContentType: .video, reference: .standalone(resource: video.resource), streamable: true, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: true)
            mediaPlayer.attachPlayerView(self.videoView)
            self.player = mediaPlayer
            
            mediaPlayer.play()
            mediaPlayer.actionAtEnd = .loop(nil)
            
            self.status = mediaPlayer.status
        }
        needsLayout = true
        
    }
    
    
    
    public override func layout() {
        super.layout()
        
        
        let vsize = NSMakeSize(1170, 1754)
        let videoSize = vsize.aspectFitted(NSMakeSize(phoneView.frame.width - 22, phoneView.frame.height - 22))

        
        switch position {
        case .top:
            self.phoneView.centerX(y: 20)
            self.videoView.frame = NSMakeRect(phoneView.frame.minX + 11, phoneView.frame.minY + 11, videoSize.width, videoSize.height)
            self.videoView.positionFlags = [.top, .left, .right]
        case .bottom:
            self.phoneView.centerX(y: frame.height - phoneView.frame.height - 20)
            self.videoView.frame = NSMakeRect(phoneView.frame.minX + 11, phoneView.frame.maxY - videoSize.height - 11, videoSize.width, videoSize.height)
            self.videoView.positionFlags = [.bottom, .left, .right]
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
