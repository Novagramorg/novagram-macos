import Cocoa
import TGUIKit
import TelegramContext
import TelegramTheme
import LocalAnimations
import SceneEffects

public final class PremiumDiamondSceneView: View, PremiumSceneView {
    #if arch(arm64)
    private let diamondLayer = InteractiveDiamondLayer()
    #else
    private let diamondFallbackView: NSView
    #endif

    public var sceneBackground: NSColor = .clear {
        didSet {
            self.backgroundColor = sceneBackground
        }
    }

    public required init(frame: CGRect) {
        #if !arch(arm64)
        self.diamondFallbackView = PremiumHooks.shared.makeStickerView(NSMakeRect(0, 0, 120, 120))
        #endif

        super.init(frame: frame)

        #if arch(arm64)
        diamondLayer.lightBackground = !theme.colors.isDark
        self.layer?.addSublayer(diamondLayer)

        self.addGestureRecognizer(NSPanGestureRecognizer(target: diamondLayer, action: #selector(InteractiveDiamondLayer.handlePan(_:))))
        self.addGestureRecognizer(NSClickGestureRecognizer(target: diamondLayer, action: #selector(InteractiveDiamondLayer.handleTap(_:))))
        #else
        self.addSubview(diamondFallbackView)
        #endif

        self.layout()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func initFallbackView(context: (any AccountContextProtocol)) {
        #if !arch(arm64)
        (diamondFallbackView as? PremiumStickerView)?.updatePremiumSticker(file: LocalAnimatedSticker.diamond.file, size: NSMakeSize(120, 120), context: context, tint: nil, animated: false)
        #endif
    }

    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        #if arch(arm64)
        diamondLayer.frame = size.bounds
        #else
        diamondFallbackView.frame = focus(NSMakeSize(120, 120))
        #endif
    }

    public override func layout() {
        super.layout()

        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    public func playAgain() {
    }

    public override func viewDidMoveToWindow() {
        #if arch(arm64)
        self.diamondLayer.isInHierarchy = window != nil
        #endif
    }
}
