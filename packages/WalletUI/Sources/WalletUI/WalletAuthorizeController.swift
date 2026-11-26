import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit

public enum WalletUIPasscodeVerification {
    case authorized
    case invalidCode
    case cooldown(Int)
    case unavailable
    case cancelled
}

public struct WalletUIAuthorizationPrompt {
    public let verify: (String, @escaping (WalletUIPasscodeVerification) -> Void) -> Void
    public let authenticateBiometrics: ((@escaping (WalletUIPasscodeVerification) -> Void) -> Void)?

    public init(verify: @escaping (String, @escaping (WalletUIPasscodeVerification) -> Void) -> Void, authenticateBiometrics: ((@escaping (WalletUIPasscodeVerification) -> Void) -> Void)?) {
        self.verify = verify
        self.authenticateBiometrics = authenticateBiometrics
    }
}

private final class WalletAuthorizeView: View {
    private let titleView = TextView()
    fileprivate let closeButton = ImageButton()
    private let descView = TextView()
    fileprivate let input = NSSecureTextField(frame: NSZeroRect)
    private let inputContainer = View()
    private let inputGlass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 18, hasShadow: true, hasBorder: true)
    private let nextButton = ImageButton()
    private let touchIdButton = ImageButton()
    fileprivate var checkImpl: () -> Void = {}
    fileprivate var useTouchIdImpl: () -> Void = {}
    private var hasTouchId: Bool = false
    private var status: String? = nil

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        addSubview(titleView)
        addSubview(closeButton)
        addSubview(descView)
        addSubview(inputGlass)
        addSubview(inputContainer)
        addSubview(nextButton)

        closeButton.setAccessibilityLabel(strings().voiceOverCommonClose)
        nextButton.setAccessibilityLabel(strings().voiceOverCommonNext)
        touchIdButton.setAccessibilityLabel(strings().passcodeUseTouchId)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        descView.userInteractionEnabled = false
        descView.isSelectable = false

        input.stringValue = ""
        input.isBordered = false
        input.usesSingleLineMode = true
        input.isBezeled = false
        input.focusRingType = .none
        input.drawsBackground = false
        input.font = .normal(.title)
        input.cell?.usesSingleLineMode = true
        input.cell?.wraps = false
        input.cell?.isScrollable = true
        input.target = self
        input.action = #selector(invokeCheck)
        input.sizeToFit()

        inputContainer.backgroundColor = .clear
        inputContainer.addSubview(input)
        inputContainer.addSubview(touchIdButton)

        nextButton.autohighlight = false
        nextButton.scaleOnClick = true
        nextButton.setFrameSize(26, 26)
        nextButton.layer?.cornerRadius = nextButton.frame.height / 2
        nextButton.set(handler: { [weak self] _ in
            self?.checkImpl()
        }, for: .SingleClick)

        touchIdButton.autohighlight = false
        touchIdButton.scaleOnClick = true
        touchIdButton.setFrameSize(26, 26)
        touchIdButton.layer?.cornerRadius = touchIdButton.frame.height / 2
        touchIdButton.set(handler: { [weak self] _ in
            self?.useTouchIdImpl()
        }, for: .SingleClick)

        updateLocalizationAndTheme(theme: theme)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invokeCheck() {
        checkImpl()
    }

    func update(hasTouchId: Bool) {
        self.hasTouchId = hasTouchId
        touchIdButton.isHidden = !hasTouchId
        nextButton.removeFromSuperview()
        if hasTouchId {
            addSubview(nextButton)
        } else {
            inputContainer.addSubview(nextButton)
        }
        input.stringValue = ""
        needsLayout = true
    }

    func update(status: String?) {
        self.status = status
        updateLocalizationAndTheme(theme: theme)
    }

    func setChecking(_ checking: Bool) {
        input.isEnabled = !checking
        nextButton.isEnabled = !checking
        touchIdButton.isEnabled = !checking
        if !checking, let window = window, window.firstResponder != input.currentEditor() {
            window.makeFirstResponder(input)
        }
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        backgroundColor = theme.colors.background
        input.backgroundColor = .clear
        input.textColor = theme.colors.text
        input.textView?.insertionPointColor = theme.colors.text

        let placeholderText = strings().walletAuthorizeControllerPasscode
        let placeholder = NSMutableAttributedString()
        _ = placeholder.append(string: placeholderText, color: theme.colors.grayText, font: .normal(.title))
        input.placeholderAttributedString = placeholder

        nextButton.set(background: walletClassicAccent, for: .Normal)
        nextButton.set(image: theme.icons.passcodeLogin, for: .Normal)

        touchIdButton.set(background: walletClassicAccent, for: .Normal)
        let touchIdIcon = NSImage(cgImage: theme.icons.passcodeTouchId, size: NSMakeSize(16, 16)).precomposed()
        touchIdButton.set(image: touchIdIcon, for: .Normal)

        let glassAppearance: LiquidGlassAppearance = theme.colors.listBackground.lightness < 0.5 ? .forceDark : .forceLight
        closeButton.set(image: NSImage(named: "Icon_Pip_Close")!.precomposed(theme.colors.text), for: .Normal)
        closeButton.setGlassEffect(size: NSMakeSize(36, 36), forceAppearance: glassAppearance)
        closeButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        closeButton.layer?.masksToBounds = false

        let titleText = strings().walletAuthorizeControllerEnterPasscode
        let titleLayout = TextViewLayout(.initialize(string: titleText, color: theme.colors.text, font: .medium(.header)), alignment: .center)
        titleLayout.measure(width: frame.width - 100)
        titleView.update(titleLayout)

        let descText: String
        let descColor: NSColor
        if let status = status {
            descText = status
            descColor = theme.colors.redUI
        } else {
            descText = strings().walletAuthorizeControllerDescription
            descColor = theme.colors.grayText
        }
        let descLayout = TextViewLayout(.initialize(string: descText, color: descColor, font: .normal(.text)), alignment: .center)
        descLayout.measure(width: frame.width - 40)
        descView.update(descLayout)

        needsLayout = true
    }

    override func layout() {
        super.layout()

        titleView.centerX(y: 20)
        closeButton.setFrameOrigin(NSMakePoint(10, 10))
        descView.centerX(y: titleView.frame.maxY + 14)

        inputContainer.setFrameSize(240, 36)
        inputContainer.centerX(y: descView.frame.maxY + 20)
        let inputRight: CGFloat
        if hasTouchId {
            inputContainer.setFrameOrigin(NSMakePoint(inputContainer.frame.minX - 18, inputContainer.frame.minY))
            nextButton.setFrameOrigin(NSMakePoint(inputContainer.frame.maxX + 10, inputContainer.frame.minY + 5))
            touchIdButton.centerY(x: inputContainer.frame.width - touchIdButton.frame.width - 5)
            inputRight = touchIdButton.frame.minX
        } else {
            nextButton.centerY(x: inputContainer.frame.width - nextButton.frame.width - 5)
            inputRight = nextButton.frame.minX
        }
        inputGlass.frame = inputContainer.frame

        input.setFrameSize(inputRight - 22, input.frame.height)
        input.centerY(x: 14)
    }
}

@available(macOS 10.15, *)
private final class WalletAuthorizeController: ModalViewController {
    private let prompt: WalletUIAuthorizationPrompt
    private let appearanceDisposable = MetaDisposable()
    private let completion: WalletUICompletion<Bool>
    private var isChecking = false
    private var cooldownRemaining = 0
    private var cooldownTimer: SwiftSignalKit.Timer?
    private var biometricsRequested = false

    init(prompt: WalletUIAuthorizationPrompt, completion: @escaping (Bool) -> Void) {
        self.prompt = prompt
        self.completion = WalletUICompletion(completion)
        super.init(frame: NSMakeRect(0, 0, 300, 168))
        self.bar = .init(height: 0)
    }

    private var genericView: WalletAuthorizeView {
        return self.view as! WalletAuthorizeView
    }

    private func finish(_ result: Bool) {
        if WalletAuthorizationPresentation.active === self {
            WalletAuthorizationPresentation.active = nil
        }
        completion.finish(result)
    }

    private func checkNextValue(_ passcode: String) {
        guard !isChecking, cooldownRemaining == 0 else {
            return
        }
        guard !passcode.isEmpty else {
            genericView.input.shake()
            return
        }
        isChecking = true
        genericView.setChecking(true)
        prompt.verify(passcode, { [weak self] result in
            self?.handle(result, silent: false)
        })
    }

    private func handle(_ result: WalletUIPasscodeVerification, silent: Bool) {
        isChecking = false
        genericView.setChecking(false)
        switch result {
        case .authorized:
            finish(true)
            close()
        case .invalidCode:
            genericView.input.stringValue = ""
            genericView.update(status: nil)
            genericView.input.shake()
        case let .cooldown(seconds):
            genericView.input.stringValue = ""
            startCooldown(seconds)
        case .unavailable:
            if !silent {
                genericView.input.stringValue = ""
                genericView.update(status: strings().walletAuthorizeControllerVerifyFailed)
            }
        case .cancelled:
            break
        }
    }

    private func startCooldown(_ seconds: Int) {
        cooldownRemaining = max(0, seconds)
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        renderCooldown()
        guard cooldownRemaining > 0 else {
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
            guard let self else {
                return
            }
            self.cooldownRemaining = max(0, self.cooldownRemaining - 1)
            self.renderCooldown()
            if self.cooldownRemaining == 0 {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
            }
        }, queue: .mainQueue())
        cooldownTimer = timer
        timer.start()
    }

    private func renderCooldown() {
        if cooldownRemaining > 0 {
            genericView.update(status: strings().walletAuthorizeControllerTooManyAttemptsOther(cooldownRemaining))
            genericView.setChecking(true)
        } else {
            genericView.update(status: nil)
            genericView.setChecking(isChecking)
        }
    }

    private func callTouchId() {
        guard let authenticate = prompt.authenticateBiometrics, !isChecking, cooldownRemaining == 0 else {
            return
        }
        isChecking = true
        genericView.setChecking(true)
        authenticate({ [weak self] result in
            self?.handle(result, silent: true)
        })
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        appearanceDisposable.set(appearanceSignal.start(next: { [weak self] appearance in
            self?.updateLocalizationAndTheme(theme: appearance.presentation)
        }))

        genericView.checkImpl = { [weak self] in
            guard let `self` = self else {
                return
            }
            self.checkNextValue(self.genericView.input.stringValue)
        }
        genericView.closeButton.set(handler: { [weak self] _ in
            self?.close()
        }, for: .SingleClick)
        genericView.useTouchIdImpl = { [weak self] in
            self?.callTouchId()
        }

        genericView.update(hasTouchId: prompt.authenticateBiometrics != nil)
        readyOnce()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestBiometricsIfNeeded()
    }

    override func windowDidBecomeKey() {
        super.windowDidBecomeKey()
        requestBiometricsIfNeeded()
    }

    private func requestBiometricsIfNeeded() {
        guard NSApp.isActive, view.window?.isKeyWindow == true, !biometricsRequested, prompt.authenticateBiometrics != nil else {
            return
        }
        biometricsRequested = true
        callTouchId()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        finish(false)
    }

    override var closable: Bool {
        return true
    }

    override func escapeKeyAction() -> KeyHandlerResult {
        finish(false)
        close()
        return .invoked
    }

    override func returnKeyAction() -> KeyHandlerResult {
        checkNextValue(genericView.input.stringValue)
        return .invoked
    }

    override func firstResponder() -> NSResponder? {
        if !(window?.firstResponder is NSText) {
            return genericView.input
        }
        let editor = self.window?.fieldEditor(true, for: genericView.input)
        if window?.firstResponder != editor {
            return genericView.input
        }
        return editor
    }

    override var handleEvents: Bool {
        return true
    }

    override var handleAllEvents: Bool {
        return true
    }

    override var responderPriority: HandlerPriority {
        return .supreme
    }

    override var shouldCloseAllTheSameModals: Bool {
        return false
    }


    override func viewClass() -> AnyClass {
        return WalletAuthorizeView.self
    }

    deinit {
        appearanceDisposable.dispose()
        cooldownTimer?.invalidate()
        finish(false)
    }
}

@available(macOS 10.15, *)
private enum WalletAuthorizationPresentation {
    static weak var active: WalletAuthorizeController?
}

@available(macOS 10.15, *)
func walletModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    return Signal { subscriber in
        let progress = showModalProgress(signal: Signal<Void, NoError>.never(), for: window, shouldPresent: { WalletAuthorizationPresentation.active == nil }).start()
        let operation = (signal |> deliverOnMainQueue).start(next: { value in
            subscriber.putNext(value)
        }, error: { error in
            subscriber.putError(error)
            progress.dispose()
        }, completed: {
            subscriber.putCompletion()
            progress.dispose()
        })
        return ActionDisposable {
            progress.dispose()
            operation.dispose()
        }
    }
}

@available(macOS 10.15, *)
@discardableResult
public func presentWalletAuthorization(_ prompt: WalletUIAuthorizationPrompt, window: Window, completion: @escaping (Bool) -> Void) -> () -> Void {
    guard WalletAuthorizationPresentation.active == nil else {
        completion(false)
        return {}
    }
    let controller = WalletAuthorizeController(prompt: prompt, completion: completion)
    WalletAuthorizationPresentation.active = controller
    showModal(with: controller, for: window)
    return { [weak controller] in
        controller?.close()
    }
}

