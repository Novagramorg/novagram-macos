import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import AlertsUI
import TelegramMedia
import PhoneNumberUtils
import LocalAnimations

public class ChaneNumberIntroView : View {
    let imageView:LottiePlayerView = LottiePlayerView()
    let textView:TextView = TextView()
    private let containerView:View = View()
    fileprivate let next = TextButton()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(containerView)
        wantsLayer = true
        containerView.addSubview(imageView)
        containerView.addSubview(textView)
        addSubview(next)
        textView.userInteractionEnabled = false
        textView.userInteractionEnabled = false
        
        next.autohighlight = false
        next.scaleOnClick = true
        
        updateLocalizationAndTheme(theme: theme)
        
    }
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        let theme = (theme as! TelegramPresentationTheme)
        if let data = LocalAnimatedSticker.change_sim.data {
            self.imageView.setFrameSize(NSMakeSize(120, 120))
            self.imageView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("change_sim"), size: NSMakeSize(120, 120), backingScale: Int(System.backingScale), fitzModifier: nil), playPolicy: .loop, colors: []))
        }
        
        backgroundColor = theme.colors.background
        textView.background = theme.colors.background
        containerView.background = theme.colors.background
        let attr = NSMutableAttributedString()
        _ = attr.append(string: strings().changePhoneNumberIntroDescription, color: theme.colors.grayText, font: .normal(.text))
        attr.detectBoldColorInString(with: .bold(.text))
        textView.set(layout: TextViewLayout(attr, alignment:.center))
        
        next.set(color: theme.colors.underSelectedColor, for: .Normal)
        next.set(background: theme.colors.accent, for: .Normal)
        next.set(font: .medium(.text), for: .Normal)
        next.set(text: strings().navigationNext, for: .Normal)
        next.sizeToFit()
        next.layer?.cornerRadius = 10
        
        needsLayout = true
    }
    
    
    public override func layout() {
        super.layout()
        containerView.setFrameSize(frame.width, 0)
        
        textView.textLayout?.measure(width: frame.width - 60)
        textView.update(textView.textLayout)
        imageView.centerX(y: 0)
        textView.centerX(y:imageView.frame.maxY + 10)
        containerView.setFrameSize(frame.width, textView.frame.maxY + 30)
        
        containerView.centerX(y: 10)
        
        next.setFrameSize(NSMakeSize(frame.width - 60, 40))
        next.centerX(y: frame.height - next.frame.height - 50 - 30)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class PhoneNumberIntroController: GenericViewController<ChaneNumberIntroView> {

    public let context: (any AccountContextProtocol)
    private let languageDisposable = MetaDisposable()

    public init(_ context: (any AccountContextProtocol)) {
        self.context = context
        super.init()
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.genericView.updateLocalizationAndTheme(theme: theme)
        requestUpdateBackBar()
        requestUpdateCenterBar()
        requestUpdateRightBar()
    }

    deinit {
        languageDisposable.dispose()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        languageDisposable.set(appearanceSignal.start(next: { [weak self] appearance in
            self?.updateLocalizationAndTheme(theme: appearance.presentation)
        }))
        
        ready.set(context.account.postbox.loadedPeerWithId(context.peerId) |> deliverOnMainQueue |> map { [weak self] peer -> Bool in
            if let phone = (peer as? TelegramUser)?.phone {
                self?.setCenterTitle(formatPhoneNumber("+" + phone))
            }
            return true
        })
        genericView.next.set(handler: { [weak self] _ in
            self?.executeNext()
        }, for: .Click)
    }
    
    
    public override var enableBack: Bool {
        return false
    }
    
    
    func executeNext() {
        alert(for: context.window, info: strings().changePhoneUseMobile)

        return
        
//        confirm(for: context.window, information: strings().changePhoneNumberIntroAlert, successHandler: { [weak self] _ in
//            if let context = self?.context {
//                self?.navigationController?.push(PhoneNumberConfirmController(context: context))
//            }
//        })
    }
    
}
