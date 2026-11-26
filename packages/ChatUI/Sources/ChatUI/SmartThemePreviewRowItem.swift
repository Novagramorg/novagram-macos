import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import AvatarUI
import GeneralRows
import Localization
import TelegramContext
import TelegramTheme
import Strings


public final class SmartThemePreviewRowItem : GeneralRowItem {
    fileprivate let theme: ThemeTuple?
    fileprivate let context: any AccountContextProtocol
    fileprivate let selected: Bool
    fileprivate let select:((ChatTheme, TelegramPresentationTheme)?)->Void
    fileprivate let emojies: [String: StickerPackItem]
    fileprivate let bubbled: Bool
    fileprivate let loading: Bool
    public init(_ initialSize: NSSize, context: any AccountContextProtocol, stableId: AnyHashable, bubbled: Bool, emojies: [String: StickerPackItem], theme: ThemeTuple?, selected: Bool, loading: Bool = false, select:@escaping((ChatTheme, TelegramPresentationTheme)?)->Void) {
        self.theme = theme
        self.select = select
        self.selected = selected
        self.context = context
        self.emojies = emojies
        self.bubbled = bubbled
        self.loading = loading
        super.init(initialSize, stableId: stableId)
    }
    
    public override var width: CGFloat {
        return 90
    }
    public override var height: CGFloat {
        return 80
    }
    
    public override func viewClass() -> AnyClass {
        return ChatThemeRowView.self
    }

    public override var accessibilityLabel: String? {
        if loading {
            return strings().voiceOverCommonLoading
        }
        guard let chatTheme = theme?.chatTheme else {
            return strings().chatChatThemeNoTheme
        }
        switch chatTheme {
        case let .emoticon(emoji):
            return emoji.strippedEmoji
        case .gift:
            return strings().voiceOverCommonGift
        }
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .radioButton
    }

    public override var accessibilityToggleState: Bool? {
        return selected
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        if let theme = theme, let chatTheme = theme.chatTheme {
            select((chatTheme, theme.theme))
        } else {
            select(nil)
        }
        return true
    }
}

private final class ChatThemeRowView: HorizontalRowView {
    private let imageView: ImageView = ImageView()
    private let emojiView = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 25, 25))
    private let emojiTextView = TextView()
    private let textView = TextView()
    private let selectionView: View = View()
    
    private var avatarView: AvatarControl?
    
    private let overlay = Control()
    
    private var noThemeTextView: TextView?
    
    private var currentTheme: ChatTheme? = nil
    
    private var progressIndicator: ProgressIndicator?
    
    private let disposable = MetaDisposable()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(emojiView)
        addSubview(emojiTextView)
        addSubview(textView)
        addSubview(selectionView)
        addSubview(overlay)
        imageView.isEventLess = true
        imageView.isAccessibilityDecorative = true
        overlay.setAccessibilityLabel(strings().voiceOverCommonSelect)
        emojiView.userInteractionEnabled = false
        selectionView.isEventLess = true
        
        textView.isSelectable = false
        textView.userInteractionEnabled = false

        
        selectionView.layer?.cornerRadius = 12
        selectionView.layer?.borderWidth = 2.5
        
        
        overlay.set(handler: { [weak self] _ in
            guard let item = self?.item as? SmartThemePreviewRowItem else {
                return
            }
            if let theme = item.theme, let chatTheme = theme.chatTheme {
                item.select((chatTheme, theme.theme))
            } else {
                item.select(nil)
            }
        }, for: .Click)

        overlay.set(handler: { [weak self] _ in
            self?.emojiView.overridePlayValue = true
        }, for: .Hover)
        
        overlay.set(handler: { [weak self] _ in
            self?.emojiView.overridePlayValue = false
        }, for: .Normal)
    }
    
    override func updateMouse(animated: Bool) {
        super.updateMouse(animated: animated)
        overlay.updateState()
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        disposable.dispose()
    }
    
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? SmartThemePreviewRowItem else {
            return
        }
        selectionView.layer?.borderColor = item.selected ? theme.colors.accentSelect.cgColor : theme.colors.border.cgColor

        var dBorder: CGFloat = 1
        if let _ = item.theme?.chatTheme {
            dBorder = item.bubbled && theme.hasWallpaper ? 0 : 1
        }
        selectionView.layer?.borderWidth = item.selected ? 2 : (item.theme == nil ? 1 : dBorder)
        
        if let current = item.theme, let chatTheme = current.chatTheme, !item.loading {
            if self.currentTheme != current.chatTheme {
                self.currentTheme = current.chatTheme
                
                let context = item.context

                switch chatTheme {
                case let .emoticon(emoji):
                    if let first = item.emojies[emoji.strippedEmoji]  {
                        let params = ChatAnimatedStickerMediaLayoutParameters(playPolicy: nil, hidePlayer: true, media: first.file._parse())
                        self.emojiView.update(with: first.file._parse(), size: NSMakeSize(25, 25), context: context, table: nil, parameters: params, animated: animated)
                        self.emojiTextView.isHidden = true
                        self.emojiView.isHidden = false
                    } else {
                        self.emojiTextView.isHidden = false
                        self.emojiView.isHidden = true
                    }
                    
                    let emojiTextLayout = TextViewLayout.init(.initialize(string: emoji.strippedEmoji, color: .black, font: .medium(18)))
                    emojiTextLayout.measure(width: .greatestFiniteMagnitude)
                    self.emojiTextView.update(emojiTextLayout)
                case let .gift(gift, _):
                    if let file = gift.unique?.file {
                        let params = ChatAnimatedStickerMediaLayoutParameters(playPolicy: nil, hidePlayer: true, media: file)
                        self.emojiView.update(with: file, size: NSMakeSize(25, 25), context: context, table: nil, parameters: params, animated: animated)
                        self.emojiTextView.isHidden = true
                        self.emojiView.isHidden = false
                    }
                }
                
                self.emojiView.overridePlayValue = false
            }
            
            switch chatTheme {
            case .emoticon:
                avatarView?.removeFromSuperview()
                avatarView = nil
            case let .gift(gift, _):
                if let themePeerId = gift.unique?.themePeerId {
                    let current: AvatarControl
                    if let view = self.avatarView {
                        current = view
                    } else {
                        current = AvatarControl(font: .avatar(11))
                        current.setFrameSize(NSMakeSize(23, 23))
                        current.userInteractionEnabled = false
                        addSubview(current)
                        self.avatarView = current
                    }
                    let signal = item.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: themePeerId)) |> deliverOnMainQueue
                    
                    disposable.set(signal.start(next: { [weak current] peer in
                        current?.setPeer(account: item.context.account, peer: peer?._asPeer())
                    }))
                    
                } else {
                    disposable.set(nil)
                    avatarView?.removeFromSuperview()
                    avatarView = nil
                }
            }
            
            self.noThemeTextView?.removeFromSuperview()
            self.noThemeTextView = nil
            self.textView.update(nil)
                        
            self.imageView.image = current.image
            self.imageView.sizeToFit()
            self.imageView.isHidden = false
            
            self.progressIndicator?.removeFromSuperview()
            self.progressIndicator = nil
        } else {
            
            avatarView?.removeFromSuperview()
            avatarView = nil
            disposable.set(nil)
            
            self.emojiTextView.update(nil)
            
            self.emojiView.isHidden = true
            
            self.imageView.image = nil
            self.imageView.isHidden = true

            if item.loading {
                self.noThemeTextView?.removeFromSuperview()
                self.noThemeTextView = nil
                
                let current: ProgressIndicator
                if let progressIndicator = self.progressIndicator {
                    current = progressIndicator
                } else {
                    current = ProgressIndicator(frame: NSMakeRect(0, 0, 30, 30))
                    current.progressColor = theme.colors.text
                    self.progressIndicator = current
                    addSubview(current)
                }
                
            } else {
                let layout = TextViewLayout(.initialize(string: "❌", color: theme.colors.text, font: .normal(15)))
                layout.measure(width: .greatestFiniteMagnitude)
                self.textView.update(layout)
                self.imageView.isHidden = true
                self.noThemeTextView?.removeFromSuperview()
                self.noThemeTextView = TextView()
                self.noThemeTextView?.isEventLess = true
                self.noThemeTextView?.userInteractionEnabled = false
                self.noThemeTextView?.isSelectable = false
                self.addSubview(self.noThemeTextView!)
                let noTheme = TextViewLayout(.initialize(string: strings().chatChatThemeNoTheme, color: theme.colors.text, font: .medium(.text)), alignment: .center)
                noTheme.measure(width: 80)
                self.noThemeTextView?.update(noTheme)
                self.progressIndicator?.removeFromSuperview()
                self.progressIndicator = nil
            }
          
        }
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        
        guard let item = item as? SmartThemePreviewRowItem else {
            return
        }
        
        self.imageView.setFrameSize(NSMakeSize(70, 80))
        self.imageView.centerX(y: 5)
        if item.selected {
            self.selectionView.frame = self.imageView.frame.insetBy(dx: -3, dy: -3)
        } else {
            self.selectionView.frame = self.imageView.frame
        }
        self.textView.centerX(y: 60)
        if let avatarView {
            avatarView.setFrameOrigin(NSMakePoint(frame.height - avatarView.frame.width - 12, 57))
            self.emojiView.setFrameOrigin(NSMakePoint(12, 55))
        } else {
            self.emojiView.centerX(y: 55)
        }
        self.noThemeTextView?.centerX(y: 15)
        self.overlay.frame = bounds
        self.progressIndicator?.center()
        self.emojiTextView.centerX(y: 55)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
}
