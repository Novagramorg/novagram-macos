import Cocoa
import TGUIKit
import SceneEffects

struct WalletSendAmountIntro {
    static let duration = InteractiveDiamondIntro.duration
    var progress: CGFloat = 1.0
    var caret: CGFloat = 1.0
    var lift: CGFloat { InteractiveDiamondIntro(progress: self.progress).lift }
    var scale: CGFloat { InteractiveDiamondIntro(progress: self.progress).scale }
    var rise: CGFloat { 56.0 * (1.0 - self.progress) }

    init(time: Double?) {
        guard let time, time < Self.duration else { return }
        let k = min(max((time - 0.78) / 0.2, 0.0), 1.0)
        self.caret = CGFloat(k * k * (3.0 - 2.0 * k))
        self.progress = InteractiveDiamondIntro(time: time).progress
    }

    func finishing(_ progress: CGFloat) -> WalletSendAmountIntro {
        var result = self
        result.progress += (1.0 - result.progress) * progress
        result.caret += (1.0 - result.caret) * progress
        return result
    }
}

struct WalletSendAmountOpeningText: Equatable {
    var shift: CGFloat = 0.0
    var alpha: CGFloat = 1.0
    var reveal = SIMD2<Float>.zero
}

func walletSendAmountOpeningText(_ opening: WalletSendAmountIntro?, width: CGFloat, gramMidX: CGFloat, textMinX: CGFloat, textMaxX: CGFloat, scale: CGFloat) -> WalletSendAmountOpeningText {
    var result = WalletSendAmountOpeningText()
    guard let opening, opening.progress < 1.0 else {
        return result
    }
    result.shift = (width / 2.0 - 64.0 * scale - (textMinX + textMaxX) / 2.0) * (1.0 - opening.progress)
    result.alpha = min(1.0, max(0.0, opening.progress) / 0.08)
    let edge = width / 2.0 + (gramMidX - width / 2.0) * opening.progress + 32.0
    result.reveal = SIMD2(Float(edge - 4.0 * scale), Float(edge + 22.0 * scale))
    return result
}

func walletSendAmountOpeningCenter(_ opening: WalletSendAmountIntro?, rect: CGRect, width: CGFloat, scale: CGFloat) -> CGPoint {
    guard let opening else {
        return CGPoint(x: rect.midX, y: rect.midY)
    }
    return CGPoint(x: width / 2.0 + (rect.midX - width / 2.0) * opening.progress, y: rect.midY + opening.lift * scale)
}

final class WalletSendOpening {
    private static let duration = 2.1
    private static let finishDuration = 0.15
    private static let animationKey = "walletSendOpening"

    private(set) var amount: WalletSendAmountIntro?
    private(set) var recipientTime: Double?
    private(set) var isFinished: Bool
    private var start: Double?
    private var pendingFinish: (start: Double, amount: WalletSendAmountIntro, recipientTime: Double)?
    private var animator: ConstantDisplayLinkAnimator?
    private let now: () -> Double

    var isReady: () -> Bool = { false }
    var updateAmount: (WalletSendAmountIntro?) -> Void = { _ in }
    var updateRecipient: (Double?) -> Void = { _ in }
    var risingViews: () -> [NSView] = { [] }

    init(now: @escaping () -> Double = CACurrentMediaTime) {
        self.now = now
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.isFinished = reduceMotion
        self.amount = reduceMotion ? nil : WalletSendAmountIntro(time: 0.0)
        self.recipientTime = reduceMotion ? nil : 0.0
    }

    deinit {
        self.animator?.invalidate()
    }

    func finish(animated: Bool) {
        guard !self.isFinished else { return }
        if animated, let start = self.start, self.pendingFinish == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let now = self.now()
            self.pendingFinish = (now, WalletSendAmountIntro(time: now - start), now - start)
            self.removeRising()
            self.update()
            return
        }
        if animated, self.pendingFinish != nil { return }
        self.isFinished = true
        self.pendingFinish = nil
        self.animator?.invalidate()
        self.animator = nil
        self.amount = nil
        self.recipientTime = nil
        self.updateAmount(nil)
        self.updateRecipient(nil)
        self.removeRising()
    }

    private func removeRising() {
        for view in self.risingViews() {
            view.layer?.removeAnimation(forKey: Self.animationKey)
        }
    }

    func update() {
        guard !self.isFinished else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            self.finish(animated: false)
            return
        }
        guard self.isReady() else { return }
        let now = self.now()
        let start = self.start ?? now
        self.start = start
        let elapsed = now - start
        var amount = WalletSendAmountIntro(time: elapsed)
        var recipientTime = elapsed
        if let pendingFinish = self.pendingFinish {
            let p = min(1.0, max(0.0, (now - pendingFinish.start) / Self.finishDuration))
            if p >= 1.0 {
                self.finish(animated: false)
                return
            }
            let k = p * p * (3.0 - 2.0 * p)
            amount = pendingFinish.amount.finishing(CGFloat(k))
            recipientTime = pendingFinish.recipientTime + (Self.duration - pendingFinish.recipientTime) * k
        } else if elapsed >= Self.duration {
            self.finish(animated: false)
            return
        }
        self.amount = elapsed < WalletSendAmountIntro.duration || self.pendingFinish != nil ? amount : nil
        self.recipientTime = recipientTime
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.updateAmount(self.amount)
        self.updateRecipient(recipientTime)
        CATransaction.commit()
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.0
        NSAnimationContext.current.timingFunction = nil
        NSAnimationContext.current.allowsImplicitAnimation = false
        for view in self.risingViews() where view.layer?.animation(forKey: Self.animationKey) == nil {
            let duration = self.pendingFinish.map { max(0.0, Self.finishDuration - (now - $0.start)) } ?? max(0.0, WalletSendAmountIntro.duration - elapsed)
            guard duration > 0.0 else { continue }
            let samples = max(2, Int(ceil(duration * 120.0)))
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
            animation.values = (0 ... samples).map { index -> CGFloat in
                let dt = duration * Double(index) / Double(samples)
                if let pendingFinish = self.pendingFinish {
                    let p = min(1.0, max(0.0, (now + dt - pendingFinish.start) / Self.finishDuration))
                    return pendingFinish.amount.rise * CGFloat(1.0 - p * p * (3.0 - 2.0 * p))
                }
                return index == samples ? 0.0 : WalletSendAmountIntro(time: elapsed + dt).rise
            }
            animation.duration = duration
            animation.isAdditive = true
            animation.calculationMode = .linear
            view.layer?.add(animation, forKey: Self.animationKey)
        }
        NSAnimationContext.endGrouping()
        if self.animator == nil {
            let animator = ConstantDisplayLinkAnimator(update: { [weak self] in
                self?.update()
            }, fps: 120)
            animator.isPaused = false
            self.animator = animator
        }
    }
}
