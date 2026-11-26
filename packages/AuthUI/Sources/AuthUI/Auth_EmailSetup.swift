import TGUIKit
import AppKit
import TelegramCore
import TelegramMedia
import FilePanels
import PhoneNumberUtils
import LocalAnimations
import TelegramContext
import TelegramTheme
import Localization
import TelegramUtils

private final class Auth_EmailSetupHeaderView : View {
    private let playerView:LottiePlayerView = LottiePlayerView()
    private let header: TextView = TextView()
    private let desc: TextView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(playerView)
        addSubview(header)
        addSubview(desc)
        header.userInteractionEnabled = false
        header.isSelectable = false

        desc.userInteractionEnabled = false
        desc.isSelectable = false

        updateLocalizationAndTheme(theme: theme)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        if let data = LocalAnimatedSticker.email_recovery.data {
            self.playerView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("email_recovery"), size: Auth_Insets.logoSize, backingScale: Int(System.backingScale), fitzModifier: nil, colors: []), playPolicy: .onceEnd))
        }

        let layout = TextViewLayout(.initialize(string: strings().authEmailSetupTitle, color: theme.colors.text, font: Auth_Insets.headerFont))
        layout.measure(width: frame.width)
        self.header.update(layout)

        let descAttr: NSAttributedString = .initialize(string: strings().authEmailSetupDescription, color: theme.colors.grayText, font: Auth_Insets.infoFont)

        let descLayout = TextViewLayout(descAttr, alignment: .center)
        descLayout.measure(width: frame.width)
        self.desc.update(descLayout)

        self.layout()
    }

    public override func layout() {
        super.layout()
        self.playerView.setFrameSize(Auth_Insets.logoSize)
        self.playerView.centerX(y: 0)
        self.header.centerX(y: self.playerView.frame.maxY + 20)
        self.desc.centerX(y: self.header.frame.maxY + 10)
    }

    public var height: CGFloat {
        return self.desc.frame.maxY
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func playAnimation() {
        playerView.playAgain()
    }
}

private final class Auth_EmailSetupInputView : View, NSTextFieldDelegate {
    private let textField: NSTextField = NSTextField()
    private var takeError: (()->Void)?
    private var invoke:(()->Void)?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textField)
        updateLocalizationAndTheme(theme: theme)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        background = theme.colors.grayBackground
        layer?.cornerRadius = 10

        textField.font = .normal(.title)
        textField.textColor = theme.colors.text
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.isBordered = false
        textField.usesSingleLineMode = true
        textField.isBezeled = false
        textField.delegate = self
        if #available(macOS 11.0, *) {
            textField.contentType = .username
        }
        textField.placeholderAttributedString = .initialize(string: strings().authEmailSetupPlaceholder, color: theme.colors.grayText, font: .normal(.text))
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            self.invoke?()
            return true
        }
        return false
    }

    public func controlTextDidChange(_ obj: Notification) {
        self.takeError?()
    }

    public func update(locked: Bool, invoke: @escaping()->Void, takeError:@escaping()->Void) {
        self.invoke = invoke
        self.takeError = takeError
        updateLocalizationAndTheme(theme: theme)
    }

    public override func layout() {
        super.layout()
        textField.frame = NSMakeRect(10, 10, frame.width - 20, 18)
    }

    public func updateLocked(_ locked: Bool) {
        self.textField.textView?.isEditable = !locked
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public func firstResponder() -> NSResponder? {
        if window?.firstResponder == textField.textView {
            return textField.textView
        }
        return textField
    }
    public var value: String {
        return self.textField.stringValue
    }
}

public final class Auth_EmailSetupView: View {
    private let container: View = View()
    private let header:Auth_EmailSetupHeaderView
    private let input:Auth_EmailSetupInputView
    private let nextView = Auth_NextView()
    private let error: LoginErrorStateView = LoginErrorStateView()
    private var locked: Bool = false

    private var takeNext:((String)->Void)?

    public required init(frame frameRect: NSRect) {
        header = Auth_EmailSetupHeaderView(frame: frameRect.size.bounds)
        input = Auth_EmailSetupInputView(frame: NSMakeRect(0, 0, 280, 40))
        super.init(frame: frameRect)
        container.addSubview(header)
        container.addSubview(input)
        container.addSubview(nextView)
        container.addSubview(error)

        addSubview(container)
        nextView.set(handler: { [weak self] _ in
            self?.invoke()
        }, for: .Click)

        updateLocalizationAndTheme(theme: theme)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        nextView.updateLocalizationAndTheme(theme: theme)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        container.setFrameSize(NSMakeSize(frame.width, header.height + Auth_Insets.betweenHeader + input.frame.height + Auth_Insets.betweenNextView + Auth_Insets.nextHeight))

        header.setFrameSize(NSMakeSize(frame.width, header.height))
        header.centerX(y: 0)
        input.centerX(y: header.frame.maxY + Auth_Insets.betweenHeader)
        error.centerX(y: input.frame.maxY + Auth_Insets.betweenError)
        nextView.centerX(y: input.frame.maxY + Auth_Insets.betweenNextView)
        container.center()
    }

    public func invoke() {
        let email = self.input.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty, email.contains("@"), !locked {
            self.takeNext?(email)
        } else if !locked {
            self.input.shake(beep: true)
        }
    }

    public func firstResponder() -> NSResponder? {
        return input.firstResponder()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public func update(locked: Bool, error: AuthorizationSendEmailCodeError?, takeNext: @escaping(String)->Void, takeError:@escaping()->Void) {
        self.input.update(locked: locked, invoke: { [weak self] in
            self?.invoke()
        }, takeError: takeError)
        self.takeNext = takeNext
        self.locked = locked
        nextView.updateLocked(locked)
        self.input.updateLocked(locked)
        if let error = error {
            let text: String
            switch error {
            case .limitExceeded:
                text = strings().loginFloodWait
            case .invalidEmail:
                text = strings().authEmailSetupErrorInvalidEmail
            case .emailNotAllowed:
                text = strings().authEmailSetupErrorEmailNotAllowed
            case .codeExpired:
                text = strings().phoneCodeExpired
            case .generic, .timeout:
                text = strings().unknownError
            }
            self.error.state.set(.error(text))
            self.input.shake(beep: true)
        } else {
            self.error.state.set(.normal)
        }
        needsLayout = true
    }

    public func playAnimation() {
        header.playAnimation()
    }
}

public final class Auth_EmailSetupController : GenericViewController<Auth_EmailSetupView> {

    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }

    public func update(locked: Bool, error: AuthorizationSendEmailCodeError?, takeNext: @escaping(String)->Void, takeError:@escaping()->Void) {
        self.genericView.update(locked: locked, error: error, takeNext: takeNext, takeError: takeError)
    }

    public override func firstResponder() -> NSResponder? {
        return genericView.firstResponder()
    }
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if animated {
            genericView.playAnimation()
        }
    }
}
