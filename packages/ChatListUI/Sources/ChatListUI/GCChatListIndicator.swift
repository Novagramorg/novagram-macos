import Cocoa
import TelegramUtils
import QuartzCore
import TGUIKit
import SwiftSignalKit

public final class GCChatListIndicator : View {

    public var color: NSColor = NSColor.white {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            (self.layer as? CAShapeLayer)?.fillColor = color.cgColor
            CATransaction.commit()
        }
    }

    public init(color: NSColor) {
        self.color = color
        super.init(frame: NSMakeRect(0, 0, 10, 20))
        self.layer = SimpleShapeLayer()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private let keyDispose = MetaDisposable()
    private var isAnimating = false
    private var animatedBounds: NSRect = .zero
    private lazy var keyObserver = WindowKeyObserver(update: { [weak self] in
        self?.updatePlayback()
    })

    deinit {
        keyDispose.dispose()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil || TelegramUtilsHooks.shared.isLite(.animations) {
            stopAnimation()
            keyDispose.set(nil)
        } else {
            startAnimation()
            if let window = window as? Window {
                keyDispose.set(window.visibility.start(next: { [weak self] value in
                    if value {
                        self?.startAnimation()
                    } else {
                        self?.stopAnimation()
                    }
                }))
            }
        }
        keyObserver.observe(window)
        updatePlayback()
    }

    public override func layout() {
        super.layout()
        if isAnimating, animatedBounds != bounds {
            startAnimation()
        }
    }

    public func startAnimation() {
        guard let layer = self.layer as? CAShapeLayer else {
            return
        }
        isAnimating = true
        animatedBounds = bounds
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = (0 ... 8).map { genPath(stage: $0 % 8, progress: 0) }
        animation.keyTimes = (0 ... 8).map { NSNumber(value: Double($0) / 8.0) }
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeOut), count: 8)
        animation.duration = 0.4 * 8
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.path = genPath(stage: 0, progress: 0)
        layer.add(animation, forKey: "path")
        CATransaction.commit()
    }

    public func stopAnimation() {
        isAnimating = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer?.removeAnimation(forKey: "path")
        (self.layer as? CAShapeLayer)?.path = genPath(stage: 8, progress: 0.5)
        CATransaction.commit()
    }

    var isIndicatorPlaying: Bool {
        return isAnimating && !(self.layer?.isTimelineFrozen ?? true)
    }

    private func updatePlayback() {
        self.layer?.setTimelineFrozen(!WindowKeyObserver.isKey(window))
    }
    
    func genPath(stage progressStage: Int, progress innerProgress: CGFloat) -> CGPath {
        let rect = self.bounds

        var size1: CGFloat = 0;
        var size2: CGFloat = 0;
        if (progressStage == 0) {
            size1 = 2 + 8 * innerProgress
            size2 = 6 - 4 * innerProgress
        } else if (progressStage == 1) {
            size1 = 10 - 8 * innerProgress
            size2 = 2 + 8 * innerProgress
        } else if (progressStage == 2) {
            size1 = 2 + 4 * innerProgress
            size2 = 10 - 8 * innerProgress
        } else if (progressStage == 3) {
            size1 = 6 - 4 * innerProgress
            size2 = 2 + 4 * innerProgress
        } else if (progressStage == 4) {
            size1 = 2 + 8 * innerProgress
            size2 = 6 - 4 * innerProgress
        } else if (progressStage == 5) {
            size1 = 10 - 8 * innerProgress
            size2 = 2 + 8 * innerProgress
        } else if (progressStage == 6) {
            size1 = 2 + 8 * innerProgress
            size2 = 10 - 8 * innerProgress
        } else {
            size1 = 10 - 8 * innerProgress
            size2 = 2 + 4 * innerProgress
        }


        let p1 = CGMutablePath()
        
        p1.addRoundedRect(in: .init(origin: NSMakePoint(0, rect.midY - size2 / 2), size: NSMakeSize(2, size2)), cornerWidth: 1, cornerHeight: 1)
        p1.addRoundedRect(in: .init(origin: NSMakePoint(4, rect.midY - size1 / 2), size: NSMakeSize(2, size1)), cornerWidth: 1, cornerHeight: 1)
        p1.addRoundedRect(in: .init(origin: NSMakePoint(8, rect.midY - size2 / 2), size: NSMakeSize(2, size2)), cornerWidth: 1, cornerHeight: 1)
        
        return p1
    }


}

