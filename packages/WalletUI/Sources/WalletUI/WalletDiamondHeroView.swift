import Cocoa
import TGUIKit
import TelegramMedia
import TelegramTheme
import SceneEffects

private let walletDiamondHeroWidthRatio: CGFloat = 78 / 118

final class WalletDiamondHeroView: Control {
    #if arch(arm64)
    private var diamondView = InteractiveDiamondView(frame: NSZeroRect)
    private var hasTransferredDiamond = false
    #else
    private let animationView = LottiePlayerView(frame: NSZeroRect)
    private var didStartAnimation = false
    #endif

    var isActive = false {
        didSet {
            updateAnimation()
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        #if arch(arm64)
        addSubview(diamondView)
        set(handler: { [weak self] _ in
            guard let self, !self.hasTransferredDiamond, !self.diamondView.isPlaying else {
                return
            }
            self.diamondView.playOnce()
        }, for: .Click)
        #else
        animationView.isEventLess = true
        addSubview(animationView)
        set(handler: { [weak self] _ in
            self?.animationView.playAgain()
        }, for: .Click)
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        #if arch(arm64)
        diamondView.frame = bounds
        #else
        animationView.frame = bounds
        #endif
    }

    #if arch(arm64)
    @available(macOS 10.15, *)
    func takeTransferDiamond() -> WalletSendTransferAnimationSource? {
        guard !hasTransferredDiamond, isActive,
              let source = WalletSendTransferAnimationSource.capture(diamond: diamondView, width: frame.width * walletDiamondHeroWidthRatio) else {
            return nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        hasTransferredDiamond = true
        let diamond = diamondView
        diamondView = InteractiveDiamondView(frame: NSZeroRect)
        diamond.prepareForWalletTransfer()
        diamond.spin(walletSendTransferSpin.velocity, decay: walletSendTransferSpin.decay)
        return source
    }

    private func updateAnimation() {
        guard !hasTransferredDiamond else {
            return
        }
        if isActive {
            diamondView.update(size: frame.size, diamondWidth: frame.width * walletDiamondHeroWidthRatio, isVisible: true, lightBackground: !theme.colors.isDark, animationMode: .lottie(loop: false), animateOnAppear: true)
        } else {
            diamondView.isRenderingEnabled = false
        }
    }
    #else
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        guard isActive, window != nil else {
            animationView.set(nil)
            didStartAnimation = false
            return
        }
        guard !didStartAnimation, let url = Bundle.main.url(forResource: "wallet_diamond", withExtension: "tgs"), let data = try? Data(contentsOf: url) else {
            return
        }
        didStartAnimation = true
        animationView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("wallet_diamond"), size: frame.size), cachePurpose: .none, playPolicy: .onceEnd, maximumFps: 60))
    }
    #endif
}
