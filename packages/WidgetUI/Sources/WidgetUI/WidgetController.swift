import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils

private final class WidgetNavigationButton : Control {


    enum Direction {
        case left
        case right
    }

    private let textView = TextView()
    private let iconLayer = SimpleLayer()
    private var glassView: LiquidGlassView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: true, hasBorder: true, tintAlpha: 0.4)
        addSubview(glass)
        glassView = glass
        addSubview(textView)
        iconLayer.masksToBounds = true
        iconLayer.zPosition = 1
        layer?.addSublayer(iconLayer)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        self.layer?.masksToBounds = false
        self.interactiveGlassView = glass
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)

        _ = theme
        self.background = .clear
    }
    
    private var direction: Direction?

    func setup(_ text: String, image: CGImage, direction: Direction) {
        self.direction = direction

        let textColor: NSColor
        textColor = theme.colors.text


        let layout = TextViewLayout(.initialize(string: text, color: textColor, font: .medium(.text)))
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)

        let tinted = TelegramThemeHooks.shared.image(.iconGeneralNext).precomposed(theme.colors.text, flipHorizontal: direction == .left)
        iconLayer.contents = tinted
        iconLayer.frame.size = tinted.backingSize
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func layout() {
        super.layout()

        glassView?.frame = bounds

        let x = round((frame.width - (textView.frame.width + 4 + iconLayer.frame.width)) / 2.0)
        let iconY = round((frame.height - iconLayer.frame.height) / 2.0)
        
        if let direction = direction {
            switch direction {
            case .left:
                iconLayer.frame.origin = NSMakePoint(x, iconY)
                textView.centerY(x: x + iconLayer.frame.width + 4)
            case .right:
                textView.centerY(x: x)
                iconLayer.frame.origin = NSMakePoint(textView.frame.maxX + 4, iconY)
            }
        }
    }
    
    func size() -> NSSize {
        return NSMakeSize(28 + textView.frame.width + 4 + iconLayer.frame.width, 32)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WidgetListView: View {
    
    enum PresentMode {
        case immidiate
        case leftToRight
        case rightToLeft
        
        var animated: Bool {
            return self != .immidiate
        }
    }
    
    private let documentView = View()
    
    private var controller: ViewController?
    
    private var prev: WidgetNavigationButton?
    private var next: WidgetNavigationButton?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
        documentView.layer?.masksToBounds = false
        addSubview(documentView)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var _next:(()->Void)?
    var _prev:(()->Void)?

    
    func present(controller: ViewController, hasNext: Bool, hasPrev: Bool, mode: PresentMode) {
        let previous = self.controller
        self.controller = controller
        
        let duration: Double = 0.5
        
        if let previous = previous {
            if mode.animated {
                previous.view._change(opacity: 0, duration: duration, timingFunction: .spring, completion: { [weak previous] completed in
                    if completed {
                        previous?.removeFromSuperview()
                    }
                })
            } else {
                previous.removeFromSuperview()
            }
        }
        
        documentView.addSubview(controller.view)
        controller.view.centerX(y: 0)

        controller.view._change(opacity: 1, animated: mode.animated, duration: duration, timingFunction: .spring)
        if mode.animated {
            let to = controller.view.frame.origin
            let from: NSPoint
            switch mode {
            case .leftToRight:
                from = NSMakePoint(to.x - 50, to.y)
            case .rightToLeft:
                from = NSMakePoint(to.x + 50, to.y)
            default:
                from = to
            }
            controller.view.layer?.animatePosition(from: from, to: to, duration: duration, timingFunction: .spring)
        }
        
        if hasPrev {
            if self.prev == nil {
                self.prev = .init(frame: .zero)
                if let prev = prev {
                    addSubview(prev)
                }
                prev?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                self.prev?.set(handler: { [weak self] _ in
                    self?._prev?()
                }, for: .Click)
            }
        } else if let prev = self.prev {
            prev.userInteractionEnabled = false
            performSubviewRemoval(prev, animated: mode.animated)
            self.prev = nil
        }
        if hasNext {
            if self.next == nil {
                self.next = .init(frame: .zero)
                if let next = next {
                    addSubview(next)
                }
                next?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                self.next?.set(handler: { [weak self] _ in
                    self?._next?()
                }, for: .Click)
            }
        } else if let next = self.next {
            next.userInteractionEnabled = false
            performSubviewRemoval(next, animated: mode.animated)
            self.next = nil
        }
        updateLocalizationAndTheme(theme: theme)
        
        needsLayout = true
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        backgroundColor = .clear
        documentView.backgroundColor = .clear
        
        let theme = theme as! TelegramPresentationTheme
        
        if let prev = prev {
            prev.setup(strings().emptyChatNavigationPrev, image: theme.emptyChatNavigationPrev, direction: .left)
            prev.setFrameSize(prev.size())
        }
        if let next = next {
            next.setup(strings().emptyChatNavigationNext, image: theme.emptyChatNavigationNext, direction: .right)
            next.setFrameSize(next.size())
        }
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        documentView.frame = NSMakeRect(0, 0, frame.width, 320)
        
        guard let controller = controller else {
            return
        }
        controller.view.centerX(y: 0)
        
        if let prev = prev {
            prev.setFrameOrigin(NSMakePoint(controller.frame.minX, documentView.frame.maxY + 10))
        }
        if let next = next {
            next.setFrameOrigin(NSMakePoint(controller.frame.maxX - next.frame.width, documentView.frame.maxY + 10))
        }
    }
}

final class WidgetController<Context: AccountContextProtocol> : TelegramGenericViewController<WidgetListView, Context> {
    
    override var defaultBarTitle: String {
        return localizedString("Telegram.WidgetController")
    }
    
    private var controllers:[ViewController] = []
    
    private var selected: Int = 0
    private var disposable: Disposable?
    
    override init(_ context: Context) {
        super.init(context)
        self.bar = .init(height: 0)
    }
    
    private func loadController(_ controller: ViewController) {
        controller._frameRect = NSMakeRect(0, 0, 320, 320)
        controller.bar = .init(height: 0)
        controller.loadViewIfNeeded()
    }
    
    private func presentSelected(_ mode: WidgetListView.PresentMode) {
        let controller = controllers[selected]
        loadController(controller)
        genericView.present(controller: controller, hasNext: true, hasPrev: true, mode: mode)
    }
    
    override func backKeyAction() -> KeyHandlerResult {
        if prev() {
            return .invoked
        }
        return .rejected
    }
    override func nextKeyAction() -> KeyHandlerResult {
        if next() {
            return .invoked
        }
        return .rejected
    }
    
    @discardableResult private func next() -> Bool {
        if selected < controllers.count - 1 {
            selected += 1
        } else {
            selected = 0
        }
        presentSelected(.rightToLeft)
        runTimer()
        return true

    }
    @discardableResult private func prev() -> Bool {
        if selected > 0 {
            selected -= 1
        } else {
            selected = controllers.count - 1
        }
        presentSelected(.leftToRight)
        runTimer()
        return true

    }
    override func viewDidLoad() {
        super.viewDidLoad()
        
        controllers.append(WidgetAppearanceController(context))
        #if BETA || STABLE
        controllers.append(WidgetAppIconController(context))
        #endif

        controllers.append(WidgetStickersController(context))
        controllers.append(WidgetRecentPeersController(context))
     
        let current = controllers[selected]
        
        loadController(current)
        
        ready.set(current.ready.get())
        
        genericView.present(controller: current, hasNext: true, hasPrev: true, mode: .immidiate)
        
        genericView._next = { [weak self] in
            self?.next()
        }
        genericView._prev = { [weak self] in
            self?.prev()
        }
        
        var currentMouseInside = false
        
        context.window.set(mouseHandler: { [weak self] _ in
            let mouseInside = self?.genericView.mouseInside() ?? false
            if mouseInside {
                self?.disposable?.dispose()
            }
            if currentMouseInside != mouseInside {
                currentMouseInside = mouseInside
                if !mouseInside {
                    self?.runTimer()
                }
            }
            return .rejected
        }, with: self, for: .mouseMoved)
        
        runTimer()
    }
    
    private func runTimer() {
//        self.disposable?.dispose()
//        
//        self.disposable = delaySignal(10).startStrict(completed: { [weak self] in
//            self?.next()
//        })
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    deinit {
        disposable?.dispose()
        context.window.removeAllHandlers(for: self)
    }
}
