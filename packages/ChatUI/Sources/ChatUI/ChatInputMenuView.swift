import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramMedia
import Cocoa
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import LocalAnimations

public final class ChatInputMenuView : View {
    private let button = Control()
    private let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 999, hasShadow: false, hasBorder: false)
    private let accentFill = View(frame: NSZeroRect)
    private let animationView: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 30, 30))
    public weak var chatInteraction: ChatInteraction?
    private var botMenu: ChatPresentationInterfaceState.BotMenu?
    private var text: TextView?
    private var compact: Bool = false
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        addSubview(button)
        button.layer?.masksToBounds = false

        button.addSubview(glass)
        accentFill.layer?.cornerRadius = 17
        accentFill.layer?.masksToBounds = true
        button.addSubview(accentFill)
        button.addSubview(animationView)
        button.scaleOnClick = true
        button.setAccessibilityLabel(strings().voiceOverCommonBotMenu)
        button.layer?.cornerRadius = 20
        button.stretchReferenceView = glass

        self.layer?.masksToBounds = false


        updateLocalizationAndTheme(theme: theme)
        
        button.set(handler: { [weak self] _ in
            if let botMenu = self?.botMenu {
                switch botMenu.menuButton {
                case .commands:
                    self?.chatInteraction?.update {
                        $0.updateBotMenu { current in
                            var current = current
                            if let value = current {
                                current?.revealed = !value.revealed
                            }
                            return current
                        }
                    }
                case let .webView(text, url):
                    self?.chatInteraction?.openWebviewFromMenu(buttonText: text, url: url)
                }
            }
            
        }, for: .Click)

    }

    public func setInnerGlassHidden(_ hidden: Bool) {
        glass.isHidden = hidden
    }

    public func setSharedGlassGhost(_ ghost: NSView?) {
        button.additionalGlassEffectView = ghost
    }

    public var glassFrame: NSRect {
        return button.frame
    }


    public func update(_ botMenu: ChatPresentationInterfaceState.BotMenu, compact: Bool = false, animated: Bool) {

        let previous = self.botMenu
        self.botMenu = botMenu
        if case let .webView(text, _) = botMenu.menuButton, !text.isEmpty {
            button.setAccessibilityLabel(text)
        } else {
            button.setAccessibilityLabel(strings().voiceOverCommonBotMenu)
        }
        self.compact = compact

        let sticker: LocalAnimatedSticker
        let playPolicy: LottiePlayPolicy

        switch botMenu.menuButton {
        case .webView:
            sticker = .bot_menu_web_app
        default:
            if botMenu.revealed {
                sticker = .bot_menu_close
            } else {
                sticker = .bot_close_menu
            }
        }

        if previous == nil || previous?.revealed == botMenu.revealed || !animated {
            playPolicy = .toEnd(from: .max)
        } else {
            playPolicy = .toEnd(from: 0)
        }

        if let data = sticker.data {
            animationView.set(.init(compressed: data, key: .init(key: .bundle(sticker.rawValue + theme.colors.name), size: NSMakeSize(30, 30)), cachePurpose: .none, playPolicy: playPolicy, colors: [.init(keyPath: "", color: theme.colors.underSelectedColor)], runOnQueue: .mainQueue()))
        }

        if compact {
            if let view = self.text {
                performSubviewRemoval(view, animated: animated)
                self.text = nil
            }
        } else {
            switch botMenu.menuButton {
            case let .webView(text, _):
                let current: TextView
                var isNew: Bool = false
                if let view = self.text {
                    current = view
                } else {
                    current = TextView()
                    current.isSelectable = false
                    current.userInteractionEnabled = false
                    self.text = current
                    isNew = true
                    button.addSubview(current)
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }
                let layout = TextViewLayout(.initialize(string: text, color: theme.colors.underSelectedColor, font: .medium(.text)))
                layout.measure(width: .greatestFiniteMagnitude)
                current.update(layout)
                if isNew {
                    current.centerY()
                }
            default:
                if let view = self.text {
                    performSubviewRemoval(view, animated: animated)
                    self.text = nil
                }
            }
        }
        button.set(background: .clear, for: .Normal)
        button.set(background: .clear, for: .Hover)
        button.set(background: .clear, for: .Highlight)
        glass.customTint = nil
        accentFill.backgroundColor = theme.colors.accent
    }

    /// Natural size for the current state. The parent (ChatInputView) drives
    /// resizing by reading this and applying it via `transition.updateFrame`.
    public var desiredSize: NSSize {
        if compact {
            return NSMakeSize(40, frame.height > 0 ? frame.height : 40)
        }
        let height: CGFloat = frame.height > 0 ? frame.height : 40
        if let botMenu = botMenu, case .webView = botMenu.menuButton, let text = self.text {
            return NSMakeSize(text.frame.width + 67, height)
        }
        return NSMakeSize(60, height)
    }

    deinit {
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        button.set(background: .clear, for: .Normal)
        button.set(background: .clear, for: .Hover)
        button.set(background: .clear, for: .Highlight)
        glass.customTint = nil
        accentFill.backgroundColor = (theme as! TelegramPresentationTheme).colors.accent
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if button.frame == .zero && transition.isAnimated {
            let compact = self.compact
            self.compact = true
            updateLayout(size: size, transition: .immediate)
            self.compact = compact
            button.frame.origin.x -= text.map { $0.frame.width + 10 } ?? 0
            text?.centerY(button, x: 38)
        }
        let buttonSize: NSSize
        if let textView = self.text, !compact {
            buttonSize = NSMakeSize(50 + textView.frame.width, 40)
        } else {
            buttonSize = NSMakeSize(40, 40)
        }
        let buttonOriginY = floor((size.height - buttonSize.height) / 2)
        let buttonFrame = NSMakeRect(size.width - buttonSize.width, buttonOriginY, buttonSize.width, buttonSize.height)
        transition.updateFrame(view: button, frame: buttonFrame)

        let buttonBounds = NSRect(origin: .zero, size: buttonSize)
        transition.updateFrame(view: glass, frame: buttonBounds)
        glass.updateLayout(size: buttonSize, transition: transition)
        transition.updateFrame(view: accentFill, frame: buttonBounds.insetBy(dx: 3, dy: 3))

        let animSize = animationView.frame.size
        let animY = floor((buttonSize.height - animSize.height) / 2)
        if let textView = self.text, !compact {
            let animFrame = NSMakeRect(5, animY, animSize.width, animSize.height)
            transition.updateFrame(view: animationView, frame: animFrame)
            let textY = floor((buttonSize.height - textView.frame.height) / 2)
            let textFrame = NSMakeRect(animFrame.maxX + 3, textY, textView.frame.width, textView.frame.height)
            transition.updateFrame(view: textView, frame: textFrame)
        } else {
            let animX = floor((buttonSize.width - animSize.width) / 2)
            let animFrame = NSMakeRect(animX, animY, animSize.width, animSize.height)
            transition.updateFrame(view: animationView, frame: animFrame)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
