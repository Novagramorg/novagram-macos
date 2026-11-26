import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramTheme

public final class GiftButtonStarsView : View {

    private static let starImage: CGImage = TelegramThemeHooks.shared.image(.starReactionParticle).precomposed(.white)
    private static let starsCount: Int = 9
    private static let starSize = NSMakeSize(6, 8)

    private let stars: [ImageView]
    private var timer: SwiftSignalKit.Timer?

    public required init(frame frameRect: NSRect) {
        var stars: [ImageView] = []
        for _ in 0 ..< GiftButtonStarsView.starsCount {
            let view = ImageView()
            view.contentGravity = .resizeAspect
            view.image = GiftButtonStarsView.starImage
            view.setFrameSize(GiftButtonStarsView.starSize)
            view.layer?.opacity = 0
            view.isEventLess = true
            view.isAccessibilityDecorative = true
            stars.append(view)
        }
        self.stars = stars

        super.init(frame: frameRect)

        for star in stars {
            addSubview(star)
        }

        self.userInteractionEnabled = false
        self.isEventLess = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard timer == nil else {
            return
        }
        seed()
        let timer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
            self?.seed()
        }, queue: Queue.mainQueue())
        timer.start()
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        for star in stars {
            star.layer?.removeAllAnimations()
            star.layer?.opacity = 0
        }
    }

    private func seed() {
        guard window != nil else {
            return
        }
        let size = frame.width > 0 && frame.height > 0 ? frame.size : NSMakeSize(72, 34)
        for star in stars {
            guard let layer = star.layer else {
                continue
            }
            guard layer.animation(forKey: "transform") == nil, layer.animation(forKey: "opacity") == nil else {
                continue
            }

            let point = NSMakePoint(CGFloat.random(in: 0 ..< size.width) - star.frame.width / 2, CGFloat.random(in: 0 ..< size.height) - star.frame.height / 2)
            star.setFrameOrigin(point)

            layer.opacity = 1

            let scale = CGFloat.random(in: 0.8 ..< 1.0)
            let duration = Double(CGFloat.random(in: 0.4 ..< 0.65))

            layer.animateScaleCenter(from: 0.001, to: scale, duration: duration, removeOnCompletion: false, completion: { [weak self, weak layer] _ in
                guard let self, let layer else {
                    return
                }
                layer.opacity = 0
                layer.animateAlpha(from: 1, to: 0, duration: Double(CGFloat.random(in: 0.3 ..< 0.35)), removeOnCompletion: false, completion: { [weak self, weak layer] _ in
                    layer?.removeAllAnimations()
                    self?.seed()
                })
            })
        }
    }
}
