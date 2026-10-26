import FenixuzCore // Fenixuz
import Foundation
import TGUIKit
import AppKit
import TelegramCore
import SwiftSignalKit
import TelegramMedia
import FilePanels
import PhoneNumberUtils
import LocalAnimations
import TelegramContext
import TelegramTheme
import Localization
import TelegramUtils
import PhoneInputUI

public final class Auth_LoginHeader : View {
    private let logo: NSImageView = NSImageView(frame: Auth_Insets.logoSize.bounds) // Fenixuz
    private let header: TextView = TextView()
    private let desc: TextView = TextView()
    private var descAttr: NSAttributedString?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(logo)
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
        
        
        updateLottie()
        
        let layout = TextViewLayout(.initialize(string: appName, color: theme.colors.text, font: Auth_Insets.headerFont))
        layout.measure(width: frame.width)
        self.header.update(layout)
        
        let descAttr: NSAttributedString = .initialize(string: strings().loginNewPhoneNumber, color: theme.colors.grayText, font: Auth_Insets.infoFont)
        let descLayout = TextViewLayout(descAttr, alignment: .center)
        descLayout.measure(width: frame.width)
        self.desc.update(descLayout)
        
        self.layout()
    }
    
    private func updateLottie() {
        self.logo.image = NSApp.applicationIconImage // Fenixuz
        self.logo.imageScaling = .scaleProportionallyUpOrDown // Fenixuz
        
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLottie()
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

public final class Auth_PhoneNumberView : View {
    private let header:Auth_LoginHeader
    private let container: View = View()
    private let input: Auth_PhoneInput = Auth_PhoneInput(frame: .zero)

    private let qrButton: TextButton = TextButton()
    private let passkeyButton: TextButton = TextButton()
    private let nextView: Auth_NextView = Auth_NextView()

    private var qrEnabled: Bool = false
    private var isUserUpdated: Bool = false
    private var passkeyAvailable: Bool = false

    fileprivate let errorLabel:LoginErrorStateView = LoginErrorStateView()

    private var takeToken:(()->Void)?
    private var takeNext:((String)->Void)?
    fileprivate let botTokenButton = TextButton() // Fenixuz
    fileprivate var takeBotToken: (() -> Void)? // Fenixuz
    private var loginWithPasskey:(()->Void)?

    private var locked: Bool = false
    
    public required init(frame frameRect: NSRect) {
        header = Auth_LoginHeader(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        container.addSubview(header)
        container.addSubview(input)

        errorLabel.layer?.opacity = 0
        container.addSubview(errorLabel)

        container.addSubview(qrButton)
        container.addSubview(passkeyButton)
        container.addSubview(nextView)

        nextView.scaleOnClick = true
        qrButton.scaleOnClick = true
        passkeyButton.scaleOnClick = true

        nextView.set(handler: { [weak self] _ in
            self?.invokeNext()
        }, for: .Click)

        qrButton.set(handler: { [weak self] _ in
            self?.takeToken?()
        }, for: .Click)

        passkeyButton.set(handler: { [weak self] _ in
            self?.loginWithPasskey?()
        }, for: .Click)

        passkeyButton.isHidden = true
        if FenixuzLoginFeatures.botToken { container.addSubview(botTokenButton); botTokenButton.set(handler: { [weak self] _ in self?.takeBotToken?() }, for: .Click) } // Fenixuz

        addSubview(container)

        updateLocalizationAndTheme(theme: theme)
    }
    
    private func invokeNext() {
        guard !locked else {
            return
        }
        self.takeNext?(self.input.readyValue)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        self.header.setFrameSize(NSMakeSize(frame.width, self.header.height))

        qrButton.set(font: Auth_Insets.infoFontBold, for: .Normal)
        qrButton.style = ControlStyle(font: .medium(15.0), foregroundColor: theme.colors.accent, backgroundColor: .clear)
        qrButton.set(text: strings().loginQRLogin, for: .Normal)
        qrButton.sizeToFit(NSMakeSize(30, 0), NSMakeSize(0, Auth_Insets.nextHeight), thatFit: true)

        passkeyButton.set(font: Auth_Insets.infoFontBold, for: .Normal)
        passkeyButton.style = ControlStyle(font: .medium(15.0), foregroundColor: theme.colors.accent, backgroundColor: .clear)
        passkeyButton.set(text: strings().authLoginWithPasskey, for: .Normal)
        passkeyButton.sizeToFit(NSMakeSize(30, 0), NSMakeSize(0, Auth_Insets.nextHeight), thatFit: true)

        passkeyButton.scaleOnClick = true
        qrButton.scaleOnClick = true
        fenixuzStyleBotTokenLink(botTokenButton) // Fenixuz
        
        nextView.updateLocalizationAndTheme(theme: theme)

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        self.input.setFrameSize(NSMakeSize(280, 80))

        var totalHeight = self.header.height + Auth_Insets.betweenHeader + input.frame.height + Auth_Insets.betweenNextView + Auth_Insets.nextHeight
        totalHeight += 10 + passkeyButton.frame.height
        totalHeight += fenixuzBotTokenLinkHeight(botTokenButton) // Fenixuz


        self.container.setFrameSize(NSMakeSize(frame.width, totalHeight))

        self.header.centerX(y: 0)
        self.input.centerX(y: self.header.frame.maxY + Auth_Insets.betweenHeader)

        self.errorLabel.centerX(y: self.input.frame.maxY + Auth_Insets.betweenError)

        self.qrButton.centerX(y: self.input.frame.maxY + Auth_Insets.betweenNextView)
        self.nextView.centerX(y: self.input.frame.maxY + Auth_Insets.betweenNextView)

        passkeyButton.centerX(y: qrButton.frame.maxY - 10)
        botTokenButton.centerX(y: max(nextView.frame.maxY, passkeyButton.frame.maxY) + 10) // Fenixuz

        self.container.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setPhoneError(_ error: AuthorizationCodeRequestError) {
        let text:String
        switch error {
        case .invalidPhoneNumber:
            text = strings().phoneNumberInvalid
        case .limitExceeded:
            text = strings().loginFloodWait
        case .generic:
            text = "undefined error"
        case .phoneLimitExceeded:
            text = "undefined error"
        case .phoneBanned:
            text = strings().loginNewPhoneBannedError
        case .timeout:
            text = "timeout"
        case .appOutdated:
            text = "please update your app"
        }
        errorLabel.state.set(.error(text))
    }
    
    public func update(_ locked: Bool, state: UnauthorizedAccountStateContents, countries: [Country], error: AuthorizationCodeRequestError?, qrEnabled: Bool, passkeyAvailable: Bool, animated: Bool, takeToken:@escaping()->Void, takeNext: @escaping(String)->Void, loginWithPasskey: @escaping()->Void) {
        if let error = error {
            setPhoneError(error)
        } else {
            errorLabel.state.set(.normal)
        }
        self.locked = locked
        self.input.updateLocked(locked)
        switch state {
        case let .phoneEntry(countryCode, number):
            self.input.update(countryCode: countryCode, number: number)
        default:
            break
        }

        self.nextView.updateLocked(locked)

        self.qrEnabled = qrEnabled
        self.passkeyAvailable = passkeyAvailable

        self.takeNext = takeNext
        self.takeToken = takeToken
        self.loginWithPasskey = loginWithPasskey


        if !qrEnabled {
            self.qrButton.isHidden = true
            self.nextView.isHidden = false
        } else {
            if !isUserUpdated {
                self.qrButton.isHidden = false
                self.nextView.isHidden = true
            } else {
                self.qrButton.isHidden = true
                self.nextView.isHidden = false
            }
        }
        
        self.passkeyButton.isHidden = !passkeyAvailable || self.qrButton.isHidden

        input.updatePhoneNumber = { [weak self] value in
            self?.qrButton.isHidden = !value.isEmpty || !qrEnabled
            self?.nextView.isHidden = value.isEmpty && qrEnabled
            self?.isUserUpdated = !value.isEmpty
        }
        input.next = { [weak self] _ in
            self?.invokeNext()
        }
        
        input.manager = .init(countries)
        
        needsLayout = true
    }
    
    public func set(_ number: String) -> Void {
        self.input.set(number)
    }
    
    public var firstResponder: NSResponder? {
        return input.firstResponder
    }
    
}

public final class Auth_PhoneNumberController: GenericViewController<Auth_PhoneNumberView> {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }

    public func update(_ locked: Bool, state: UnauthorizedAccountStateContents, countries: [Country], error: AuthorizationCodeRequestError?, qrEnabled: Bool, passkeyAvailable: Bool, takeToken:@escaping()->Void, takeNext: @escaping(String)->Void, loginWithPasskey: @escaping()->Void) {
        self.genericView.update(locked, state: state, countries: countries, error: error, qrEnabled: qrEnabled, passkeyAvailable: passkeyAvailable, animated: true, takeToken: takeToken, takeNext: takeNext, loginWithPasskey: loginWithPasskey)
    }
    
    public func set(number: String) {
        self.genericView.set(number)
    }
    func fenixuzSetTakeBotToken(_ f: @escaping () -> Void) { genericView.takeBotToken = f } // Fenixuz
    
    public override func firstResponder() -> NSResponder? {
        return genericView.firstResponder
    }
    
    deinit {
        var bp = 0
        bp += 1
    }
}
