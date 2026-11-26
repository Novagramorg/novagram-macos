import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import AlertsUI
import SystemPermissions
import BuildConfig
import LocalAuthentication
import InputDataUI
import GeneralRows

private class TouchIdContainerView : View {
    fileprivate let button: TextButton = TextButton()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
        
        button.scaleOnClick = true
        button.autohighlight = false
        button.style = ControlStyle(font: .medium(.title), foregroundColor: theme.colors.underSelectedColor, backgroundColor: theme.colors.accent, highlightColor: theme.colors.accent)
        button.set(font: .medium(.title), for: .Normal)
        button.set(color: theme.colors.underSelectedColor, for: .Normal)

        button.set(text: strings().passcodeUseTouchId, for: .Normal)
        button.set(image: theme.icons.passcodeTouchId, for: .Normal)
        button.layer?.cornerRadius = 18
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        _ = button.sizeToFit(NSMakeSize(16, 0), NSMakeSize(0, 36), thatFit: true)
        button.centerX(y: frame.height - button.frame.height)
        
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        let (text, layout) = TextNode.layoutText(NSAttributedString.initialize(string: strings().passcodeOr, color: theme.chatServiceItemTextColor, font: .normal(.title)), theme.colors.background, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
        
        let f = focus(text.size)
        layout.draw(NSMakeRect(f.minX, 0, f.width, f.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
        
        ctx.setFillColor(theme.chatServiceItemTextColor.cgColor)
        ctx.fill(NSMakeRect(0, floorToScreenPixels(backingScaleFactor, f.height / 2), f.minX - 10, .borderSize))
        
        ctx.setFillColor(theme.chatServiceItemTextColor.cgColor)
        ctx.fill(NSMakeRect(f.maxX + 10, floorToScreenPixels(backingScaleFactor, f.height / 2), f.minX - 10, .borderSize))
    }
}

public final class PasscodeField : NSSecureTextField {
    
    public override func resignFirstResponder() -> Bool {
        (self.delegate as? PasscodeLockView)?.controlTextDidBeginEditing(Notification(name: NSControl.textDidChangeNotification))
        return super.resignFirstResponder()
    }
    
    public override func becomeFirstResponder() -> Bool {
        (self.delegate as? PasscodeLockView)?.controlTextDidEndEditing(Notification(name: NSControl.textDidChangeNotification))
        return super.becomeFirstResponder()
    }
}


public class PasscodeLockView : Control, NSTextFieldDelegate {
    private let backgroundView: BackgroundView = BackgroundView(frame: .zero)
    private let visualEffect: NSVisualEffectView = NSVisualEffectView(frame: .zero)

    
    fileprivate let nameView:TextView = TextView()
    public let input:PasscodeField
    private let nextButton:ImageButton = ImageButton()
    private var hasTouchId:Bool = false
    private let touchIdContainer:TouchIdContainerView = TouchIdContainerView(frame: NSMakeRect(0, 0, 240, 76))
    fileprivate let logoutTextView:TextView = TextView()
    public let value:ValuePromise<String> = ValuePromise(ignoreRepeated: false)
    public var logoutImpl:() -> Void = {}
    fileprivate var useTouchIdImpl:() -> Void = {}
    private let inputContainer: View = View()
    private let inputGlass: LiquidGlassView = LiquidGlassView(frame: NSZeroRect, cornerRadius: 18, hasShadow: true, hasBorder: true)
    private var fieldState: SearchFieldState = .Focus

    private static let inputSize = NSMakeSize(240, 36)
    private static let buttonSize = NSMakeSize(26, 26)
    private static let buttonInset: CGFloat = 5
    private static let textInset: CGFloat = 14
    private static let textToButtonGap: CGFloat = 8

    public required init(frame frameRect: NSRect) {
        input = PasscodeField(frame: NSZeroRect)
        input.stringValue = ""
        backgroundView.useSharedAnimationPhase = false
        super.init(frame: frameRect)
        
        addSubview(backgroundView)
       // addSubview(visualEffect)
        
        visualEffect.state = .active
        visualEffect.blendingMode = .withinWindow
        
        autoresizingMask = [.width, .height]
        self.backgroundColor = .clear
        
        nextButton.autohighlight = false
        nextButton.set(background: theme.colors.accentIcon, for: .Normal)
        nextButton.set(image: theme.icons.passcodeLogin, for: .Normal)
        nextButton.setFrameSize(PasscodeLockView.buttonSize)
        nextButton.scaleOnClick = true
        nextButton.layer?.cornerRadius = nextButton.frame.height / 2
        nextButton.setAccessibilityLabel(strings().voiceOverCommonUnlock)

        nameView.userInteractionEnabled = false
        nameView.isSelectable = false

//        addSubview(nameView)
        addSubview(inputGlass)
        addSubview(inputContainer)
        addSubview(logoutTextView)
        addSubview(touchIdContainer)
        input.isBordered = false
        input.usesSingleLineMode = true
        input.isBezeled = false
        input.focusRingType = .none
        input.delegate = self
        input.drawsBackground = false
        
        nameView.disableBackgroundDrawing = true
        logoutTextView.disableBackgroundDrawing = true

            
        inputContainer.backgroundColor = .clear
        inputContainer.layer?.masksToBounds = false
        inputContainer.addSubview(input)
        inputContainer.addSubview(nextButton)
        
        let attr = NSMutableAttributedString()
        _ = attr.append(string: strings().passcodeEnterPasscodePlaceholder, color: theme.colors.grayText, font: .medium(17))
        //attr.setAlignment(.center, range: attr.range)
        input.placeholderAttributedString = attr
        input.setAccessibilityLabel(strings().passcodeEnterPasscodePlaceholder)
        input.cell?.usesSingleLineMode = true
        input.cell?.wraps = false
        input.cell?.isScrollable = true
        input.font = .normal(.title)
        input.textView?.insertionPointColor = theme.colors.grayText
        
        input.sizeToFit()
        
       

        input.target = self
        input.action = #selector(checkPasscode)
        
        nextButton.set(handler: { [weak self] _ in
            self?.checkPasscode()
        }, for: .SingleClick)
        
        touchIdContainer.button.set(handler: { [weak self] _ in
            self?.useTouchIdImpl()
        }, for: .SingleClick)
        
        updateLocalizationAndTheme(theme: theme)
        layout()
    }
    
    public var secondaryColor: NSColor {
        switch theme.controllerBackgroundMode {
        case .gradient:
            return theme.chatServiceItemTextColor
        case .background:
            return theme.chatServiceItemTextColor
        default:
            if theme.chatBackground == theme.chatServiceItemColor {
                return theme.colors.text
            }
        }
        return theme.chatServiceItemTextColor
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        backgroundColor = theme.colors.background
        input.backgroundColor = .clear
        input.textView?.insertionPointColor = theme.colors.text
        input.textColor = theme.colors.text
        inputContainer.background = .clear
        backgroundView.backgroundMode = theme.controllerBackgroundMode


        let placeholder = NSMutableAttributedString()
        _ = placeholder.append(string: strings().passcodeEnterPasscodePlaceholder, color: theme.colors.grayText, font: .normal(.title))
        input.placeholderAttributedString = placeholder
        
        if #available(macOS 10.14, *) {
            visualEffect.material = .underWindowBackground
        } else {
            visualEffect.material = theme.colors.isDark ? .ultraDark : .light
        }
        
        let logoutAttr = parseMarkdownIntoAttributedString(strings().passcodeLostDescription, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.chatServiceItemTextColor), bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.chatServiceItemTextColor), link: MarkdownAttributeSet(font: .bold(.text), textColor: secondaryColor == theme.chatServiceItemTextColor ? theme.chatServiceItemTextColor : theme.colors.link), linkAttribute: { contents in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents,  {_ in}))
        }))
        
        logoutTextView.isSelectable = false
        
        let logoutLayout = TextViewLayout(logoutAttr, alignment: .center)
        
        logoutLayout.interactions = TextViewInteractions(processURL:{ [weak self] _ in
            self?.logoutImpl()
        })
        logoutLayout.measure(width: frame.width - 40)
        if theme.bubbled {
            logoutLayout.generateAutoBlock(backgroundColor: theme.chatServiceItemColor)
        }
        logoutTextView.set(layout: logoutLayout)
        
        let layout = TextViewLayout(.initialize(string: strings().passlockEnterYourPasscode, color: theme.chatServiceItemTextColor, font: .medium(17)), alignment: .center)
        
        layout.measure(width: frame.width - 40)
        if theme.bubbled {
            layout.generateAutoBlock(backgroundColor: theme.chatServiceItemColor)
        }
        nameView.update(layout)
        
        
    }
    
    public override func mouseMoved(with event: NSEvent) {
        
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        change(state: fieldState, animated: true)
        backgroundView.doAction()
    }
    

    
    public func controlTextDidBeginEditing(_ obj: Notification) {
        change(state: .Focus, animated: true)
        input.textView?.insertionPointColor = theme.colors.text
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        window?.makeFirstResponder(input)
        input.textView?.insertionPointColor = theme.colors.text
    }
    
    private func change(state: SearchFieldState, animated: Bool) {
        self.fieldState = state
        switch state {
        case .Focus:
            let width = nextButton.frame.minX - PasscodeLockView.textToButtonGap - PasscodeLockView.textInset
            input._change(size: NSMakeSize(width, input.frame.height), animated: animated)
            input._change(pos: NSMakePoint(PasscodeLockView.textInset, input.frame.minY), animated: animated)
            nextButton.change(opacity: 1, animated: animated)
        case .None:
            input.sizeToFit()
            let f = inputContainer.focus(input.frame.size)
            input._change(pos: NSMakePoint(f.minX, input.frame.minY), animated: animated)
            nextButton.change(opacity: 0, animated: animated)
        }
    }
    
    @objc public func checkPasscode() {
        value.set(input.stringValue)
    }
    
    public func update(hasTouchId: Bool) {
        self.hasTouchId = hasTouchId
        
        if hasTouchId {
            showTouchIdUI()
        } else {
            hideTouchIdUI()
        }
        
        input.stringValue = ""
       
        
        needsLayout = true

    }
    public func updateAndSetValue() {
        self.value.set(self.input.stringValue)
        self.backgroundView.doAction()
    }
    
    private func showTouchIdUI() {
        touchIdContainer.isHidden = false
    }
    
    private func hideTouchIdUI() {
        touchIdContainer.isHidden = true
    }
    

    public override func layout() {
        super.layout()
        
        backgroundView.frame = bounds
        backgroundView.updateLayout(size: frame.size, transition: .immediate)
        
        visualEffect.frame = bounds

        inputContainer.setFrameSize(PasscodeLockView.inputSize)
        inputContainer.center()

        inputGlass.cornerRadius = inputContainer.frame.height / 2
        inputGlass.frame = inputContainer.frame

        nextButton.setFrameSize(PasscodeLockView.buttonSize)
        nextButton.layer?.cornerRadius = nextButton.frame.height / 2
        nextButton.centerY(x: inputContainer.frame.width - nextButton.frame.width - PasscodeLockView.buttonInset)

        input.sizeToFit()
        input.setFrameSize(NSMakeSize(nextButton.frame.minX - PasscodeLockView.textToButtonGap - PasscodeLockView.textInset, input.frame.height))
        input.centerY(x: PasscodeLockView.textInset)

        logoutTextView.resize(frame.width - 40, blockColor: theme.chatServiceItemColor)
        nameView.resize(frame.width - 40, blockColor: theme.chatServiceItemColor)

        touchIdContainer.centerX(y: inputContainer.frame.maxY + 10)

        nameView.centerX(y: inputContainer.frame.minY - nameView.frame.height - 10)
        logoutTextView.centerX(y: frame.height - logoutTextView.frame.height - 10)
        
        
        change(state: fieldState, animated: false)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class PasscodeLockController: ModalViewController {
    public let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let useTouchId: Bool
    private let appearanceDisposable = MetaDisposable()
    private let disposable:MetaDisposable = MetaDisposable()
    private let valueDisposable = MetaDisposable()
    private let logoutDisposable = MetaDisposable()
    private let _doneValue:Promise<Bool> = Promise(false)
    private let laContext = LAContext()
    public var doneValue:Signal<Bool, NoError> {
        return _doneValue.get()
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
    private let updateCurrectController: ()->Void
    private let logoutImpl:() -> Signal<Never, NoError>
    public init(_ accountManager: AccountManager<TelegramAccountManagerTypes>, useTouchId: Bool, logoutImpl:@escaping()->Signal<Never, NoError> = { .complete() }, updateCurrectController: @escaping()->Void) {
        self.accountManager = accountManager
        self.logoutImpl = logoutImpl
        self.useTouchId = useTouchId
        self.updateCurrectController = updateCurrectController
        super.init(frame: NSMakeRect(0, 0, 350, 350))
        self.bar = .init(height: 0)
    }
    
    public override var isVisualEffectBackground: Bool {
        return false
    }
    
    public override var isFullScreen: Bool {
        return true
    }
    
    
    
    public override var background: NSColor {
        return self.containerBackground
    }
    
    private var genericView:PasscodeLockView {
        return self.view as! PasscodeLockView
    }
    
    private func checkNextValue(_ passcode: String) {
        let appEncryption = AppEncryptionParameters(path: accountManager.basePath.nsstring.deletingLastPathComponent)
        appEncryption.applyPasscode(passcode)
        if appEncryption.decrypt() != nil {
            PasscodeCredentialHooks.shared.passcodeUnlocked(passcode)
            self._doneValue.set(.single(true))
            self.close()
            
        } else {
            genericView.input.shake()
        }
    }
    
    private var touchIdCalled = false
    
    public override func windowDidBecomeKey() {
        super.windowDidBecomeKey()

        if NSApp.isActive, useTouchId, !touchIdCalled {
            callTouchId()
            touchIdCalled = true
        }
    }
    
    public override func windowDidResignKey() {
        super.windowDidResignKey()
        if !NSApp.isActive, useTouchId {
        }
    }
    
    public func callTouchId(tryAnotherWay: Bool = false) {
        laContext.evaluatePolicy(tryAnotherWay ? .deviceOwnerAuthentication : .applicationPolicy, localizedReason: strings().passcodeUnlockTouchIdReason) { [weak self] (success, evaluateError) in
            if (success) {
                Queue.mainQueue().async {
                    self?._doneValue.set(.single(true))
                    self?.close()
                }
            } else if evaluateError != nil, !tryAnotherWay {
                self?.callTouchId(tryAnotherWay: true)
            }
        }
    }
    
    public override var cornerRadius: CGFloat {
        return 0
    }
    
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.updateCurrectController()
    }
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        appearanceDisposable.set(appearanceSignal.start(next: { [weak self] appearance in
            self?.updateLocalizationAndTheme(theme: appearance.presentation)
        }))
        
        genericView.logoutImpl = { [weak self] in
            guard let window = self?.window else { return }
            
            verifyAlert_button(for: window, information: strings().accountConfirmLogoutText, successHandler: { [weak self] _ in
                guard let `self` = self else { return }
                _ = showModalProgress(signal: self.logoutImpl(), for: window).start(completed: { [weak self] in
                    delay(0.2, closure: { [weak self] in
                        self?.close()
                    })
                })
            })
           
        }
        
        genericView.useTouchIdImpl = { [weak self] in
            self?.callTouchId()
        }
                
        valueDisposable.set((genericView.value.get() |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.checkNextValue(value)
        }))
        
        genericView.update(hasTouchId: useTouchId)
        readyOnce()
        
        
    }
    
    public override var closable: Bool {
        return false
    }

    
    public override func escapeKeyAction() -> KeyHandlerResult {
        return .invoked
    }
    
    public override func returnKeyAction() -> KeyHandlerResult {
        self.genericView.updateAndSetValue()
        return .invoked
    }
    
    public override func firstResponder() -> NSResponder? {
        if !(window?.firstResponder is NSText) {
            return genericView.input
        }
        let editor = self.window?.fieldEditor(true, for: genericView.input)
        if window?.firstResponder != editor {
            return genericView.input
        }
        return editor
        
    }
    
    public override var containerBackground: NSColor {
        return theme.colors.background.withAlphaComponent(1.0)
    }
    public override var handleEvents: Bool {
        return true
    }
    
    public override var handleAllEvents: Bool {
        return true
    }
    
    
    public override var responderPriority: HandlerPriority {
        return .supreme
    }
    
    public override var shouldCloseAllTheSameModals: Bool {
        return false
    }
    
    deinit {
        disposable.dispose()
        logoutDisposable.dispose()
        valueDisposable.dispose()
        appearanceDisposable.dispose()
        self.window?.removeAllHandlers(for: self)
    }
    
    public override func viewClass() -> AnyClass {
        return PasscodeLockView.self
    }
    
}

