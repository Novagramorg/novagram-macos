import AppKit
import TGUIKit
import TelegramCore
import TelegramTheme

private let story_privacy_some_users = TelegramThemeHooks.shared.image(.iconPeerStorySomeUsers).precomposed(.white)
private let story_privacy_contacts = TelegramThemeHooks.shared.image(.iconPeerStoryContacts).precomposed(.white)
private let story_privacy_close_friends = TelegramThemeHooks.shared.image(.iconPeerStoryCloseFriends).precomposed(.white)
private let story_pinned = TelegramThemeHooks.shared.image(.iconPeerStoryPinned).precomposed(.white)

final class LegacyStoryViewsView: ShadowView {
    private static let icon = TelegramThemeHooks.shared.image(.iconChannelViews).precomposed(.white)
    
    private let imageView = ImageView()
    private let textView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        self.isEventLess = true
        self.imageView.isEventLess = true
        self.textView.isEventLess = true
        
        self.direction = .vertical(true)
        self.shadowBackground = NSColor.black.withAlphaComponent(0.25)
    }
    
    func update(_ seenCount: Int, animated: Bool) {
        let layout = TextViewLayout.init(.initialize(string: seenCount.prettyNumber, color: .white, font: .normal(.small)))
        layout.measure(width: .greatestFiniteMagnitude)
        self.textView.update(layout)
        
        self.imageView.image = LegacyStoryViewsView.icon
        self.imageView.sizeToFit()
        
    }
    
    override func layout() {
        super.layout()
        self.imageView.centerY(x: 10)
        self.textView.centerY(x: self.imageView.frame.maxX + 5)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class LegacyStoryPrivacyView: ShadowView {
    private static let icon = TelegramThemeHooks.shared.image(.iconChannelViews).precomposed(.white)
    
    private let imageView = ImageView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        
        self.isEventLess = true
        self.imageView.isEventLess = true
        
        self.direction = .vertical(false)
        self.shadowBackground = NSColor.black.withAlphaComponent(0.25)
    }
    
    func update(_ privacy: EngineStoryPrivacy, isPinned: Bool, animated: Bool) {
        
        if isPinned {
            self.imageView.image = story_pinned
        } else {
            switch privacy.base {
            case .closeFriends:
                self.imageView.image = story_privacy_close_friends
            case .everyone:
                self.imageView.image = nil
            case .contacts:
                self.imageView.image = story_privacy_contacts
            case .nobody:
                self.imageView.image = story_privacy_some_users
            }
        }
      
        self.imageView.sizeToFit()
        
    }
    
    override func layout() {
        super.layout()
        self.imageView.centerY(x: frame.width - imageView.frame.width - 5)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
