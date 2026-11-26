import Foundation



import Foundation
import TGUIKit
import AppKit
import TelegramCore
import SwiftSignalKit
import FilePanels
import PhoneNumberUtils
import LocalAnimations
import TelegramContext
import TelegramTheme
import Localization
import TelegramUtils

public final class Auth_SignupHeader : View {
    private let logo:ImageButton = ImageButton(frame: Auth_Insets.logoSize.bounds)
    private let header: TextView = TextView()
    private let desc: TextView = TextView()
    
    public private(set) var selectedPath: String? {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }
    
    private var descAttr: NSAttributedString?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(logo)
        addSubview(header)
        addSubview(desc)
        header.userInteractionEnabled = false
        header.isSelectable = false
        
        logo.setAccessibilityLabel(strings().voiceOverCommonProfilePhoto)
        logo.scaleOnClick = true
        logo.autohighlight = false
        
        desc.userInteractionEnabled = false
        desc.isSelectable = false
        
        logo.contextMenu = { [weak self] in
            
            let menu = ContextMenu()
            
            menu.addItem(ContextMenuItem(strings().loginNewRegisterSelect, handler: { [weak self] in
                guard let window = self?._window else {
                    return
                }
                filePanel(with: photoExts, allowMultiple: false, canChooseDirectories: false, for: window, completion: { paths in
                    if let path = paths?.first {
                        self?.selectedPath = path
                    }
                })
            }, itemImage: MenuAnimation.menu_shared_media.value))
            
            if self?.selectedPath != nil {
                menu.addItem(ContextSeparatorItem())
                menu.addItem(ContextMenuItem(strings().loginNewRegisterRemove, handler: { [weak self] in
                    self?.selectedPath = nil
                }, itemImage: MenuAnimation.menu_delete.value))
            }
            return menu
        }
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        if let path = selectedPath, let image = NSImage(contentsOf: URL(fileURLWithPath: path)) {
            self.logo.set(image: generateImage(Auth_Insets.logoSize, contextGenerator: { size, ctx in
                ctx.clear(size.bounds)
                ctx.setFillColor(theme.colors.accent.cgColor)
                ctx.fillEllipse(in: size.bounds)
                let image = image._cgImage!
                let imgSize = image.systemSize.aspectFilled(size)
                ctx.round(size, size.height / 2)
                ctx.draw(image, in: size.bounds.focus(imgSize))
            })!, for: .Normal)
        } else {
            self.logo.set(image: generateImage(Auth_Insets.logoSize, contextGenerator: { size, ctx in
                ctx.clear(size.bounds)
                ctx.setFillColor(theme.colors.accent.cgColor)
                ctx.fillEllipse(in: size.bounds)
                let image = TelegramThemeHooks.shared.image(.iconRegisterAddPhoto).precomposed(theme.colors.underSelectedColor)
                ctx.draw(image, in: size.bounds.focus(image.backingSize))
            })!, for: .Normal)
        }
        
        
        let layout = TextViewLayout(.initialize(string: strings().loginNewRegisterHeader, color: theme.colors.text, font: Auth_Insets.headerFont))
        layout.measure(width: frame.width)
        self.header.update(layout)
        
        let descAttr: NSAttributedString = .initialize(string: strings().loginNewRegisterInfo, color: theme.colors.grayText, font: Auth_Insets.infoFont)
        let descLayout = TextViewLayout(descAttr, alignment: .center)
        descLayout.measure(width: frame.width)
        self.desc.update(descLayout)
        
        self.layout()
    }
    
    public func update(desc: NSAttributedString) {
        self.descAttr = desc
        updateLocalizationAndTheme(theme: theme)
    }
    
    public override func layout() {
        super.layout()
        self.logo.centerX(y: 0)
        self.header.centerX(y: self.logo.frame.maxY + 20)
        self.desc.centerX(y: self.header.frame.maxY + 10)

    }
    
    public var height: CGFloat {
        return self.desc.frame.maxY
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class Auth_SignPhoneInput: View, NSTextFieldDelegate {
    private let separator = View()
    
    private let firstText:NSTextField = NSTextField()
    private let lastText:NSTextField = NSTextField()
    
    public var next:(()->Void)?
        
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(separator)
        layer?.cornerRadius = 10
        
        
        firstText.font = .normal(.title)
        lastText.font = .normal(.title)
        
        firstText.isBordered = false
        firstText.isBezeled = false
        firstText.focusRingType = .none
        firstText.drawsBackground = false
        
        lastText.isBordered = false
        lastText.isBezeled = false
        lastText.focusRingType = .none
        lastText.drawsBackground = false
        
        lastText.delegate = self
        lastText.nextResponder = firstText
        lastText.nextKeyView = firstText
        
        firstText.delegate = self
        firstText.nextResponder = lastText
        firstText.nextKeyView = lastText
        
        addSubview(lastText)
        addSubview(firstText)
        
        updateLocalizationAndTheme(theme: theme)

    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.backgroundColor = theme.colors.grayBackground
        self.separator.background = theme.colors.border
        lastText.backgroundColor = .clear
        firstText.backgroundColor = .clear
        firstText.textColor = theme.colors.text
        lastText.textColor = theme.colors.text

        lastText.placeholderAttributedString = .initialize(string: "Last Name", color: theme.colors.grayText, font: .normal(.header))
        firstText.placeholderAttributedString = .initialize(string: "First Name", color: theme.colors.grayText, font: .normal(.header))
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        firstText.setFrameSize(frame.width - 20, 18)
        lastText.setFrameSize(frame.width - 20, 18)
        
        self.separator.frame = focus(NSMakeSize(frame.width - 20, .borderSize))
        firstText.setFrameOrigin(10, floor((frame.height / 2 - firstText.frame.height/2) / 2))
        lastText.setFrameOrigin(10, frame.height - floor(frame.height / 2 - lastText.frame.height/2))
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        needsLayout = true
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        return false
    }

    public func set(firstName: String, lastName: String) {
        self.firstText.stringValue = firstName
        self.lastText.stringValue = lastName
    }
    
    public var readyValue: (String, String) {
        return (self.firstText.stringValue, self.lastText.stringValue)
    }
    
    public func shakeFirst() {
        self.firstText.shake()
    }
    
    public var firstResponder: NSResponder? {
        if window?.firstResponder != firstText.textView || window?.firstResponder != lastText.textView {
            if self.firstText.stringValue.isEmpty {
                return self.firstText
            }
            return self.lastText
        }
        return window?.firstResponder
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public final class Auth_SignupView : View {
    private let header:Auth_SignupHeader
    private let container: View = View()
    private let input = Auth_SignPhoneInput(frame: .zero)
    
    private let nextView = Auth_NextView()
    private let error: LoginErrorStateView = LoginErrorStateView()
    private let footer = TextView()
    
    private var takeNext:((String, String, String?)->Void)?
    private var takeTerms:(()->Void)?
    
    
    public required init(frame frameRect: NSRect) {
        header = Auth_SignupHeader(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        container.addSubview(header)
        container.addSubview(input)
        
        container.addSubview(nextView)
        container.addSubview(error)

//        container.addSubview(footer)

        nextView.scaleOnClick = true
        
        nextView.set(handler: { [weak self] _ in
            self?.invoke()
        }, for: .Click)
        

        addSubview(container)

        updateLocalizationAndTheme(theme: theme)
    }
    
    private func invoke() {
        if !self.input.readyValue.0.isEmpty {
            self.takeNext?(self.input.readyValue.0, self.input.readyValue.1, self.header.selectedPath)
        } else {
            self.input.shakeFirst()
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        self.header.setFrameSize(NSMakeSize(frame.width, self.header.height))
        
        let attr = parseMarkdownIntoAttributedString(strings().loginNewRegisterFooter, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: Auth_Insets.infoFont, textColor: theme.colors.grayText), bold: MarkdownAttributeSet(font: Auth_Insets.infoFontBold, textColor: theme.colors.grayText), link: MarkdownAttributeSet(font: Auth_Insets.infoFont, textColor: theme.colors.link), linkAttribute: { [self] contents in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents,  { [weak self] _ in
                self?.takeTerms?()
            }))
        }))
        
        let layout = TextViewLayout(attr)
        layout.measure(width: frame.width)
        layout.interactions = LinkHooks.shared.globalLinkExecutor()
        
        footer.update(layout)
        
        nextView.updateLocalizationAndTheme(theme: theme)
        
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        
        self.input.setFrameSize(NSMakeSize(280, 80))
        
        self.container.setFrameSize(NSMakeSize(frame.width, self.header.height + Auth_Insets.betweenHeader + input.frame.height + Auth_Insets.betweenNextView + Auth_Insets.nextHeight))
        
        self.header.centerX(y: 0)
        self.input.centerX(y: self.header.frame.maxY + Auth_Insets.betweenHeader)
        self.error.centerX(y: input.frame.maxY + Auth_Insets.betweenError)
        self.nextView.centerX(y: self.input.frame.maxY + Auth_Insets.betweenNextView)
        self.footer.centerX(y: self.nextView.frame.maxY + Auth_Insets.betweenHeader)

        self.container.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(_ locked: Bool, error: SignUpError?, takeNext: @escaping(String, String, String?)->Void, takeTerms:@escaping()->Void) {
        nextView.updateLocked(locked, string: strings().loginNewRegisterNext)
        self.takeNext = takeNext
        self.takeTerms = takeTerms
        
        
        if let error = error {
            let text: String
            switch error {
            case .limitExceeded:
                text = strings().loginFloodWait
            case .codeExpired:
                text = strings().phoneCodeExpired
            case .invalidFirstName:
                text = strings().loginInvalidFirstNameError
            case .invalidLastName:
                text = strings().loginInvalidLastNameError
            case .generic:
                text = strings().unknownError
            }
            self.error.state.set(.error(text))
        } else {
            self.error.state.set(.normal)
        }
        
        needsLayout = true
    }
    
    public var firstResponder: NSResponder? {
        return input.firstResponder
    }
    
}

public final class Auth_SignupController: GenericViewController<Auth_SignupView> {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }
    
    public func update(_ locked: Bool, error: SignUpError?, takeNext: @escaping(String, String, String?)->Void, takeTerms:@escaping()->Void) {
        self.genericView.update(locked, error: error, takeNext: takeNext, takeTerms: takeTerms)
    }
    
    public override func firstResponder() -> NSResponder? {
        return genericView.firstResponder
    }
}

