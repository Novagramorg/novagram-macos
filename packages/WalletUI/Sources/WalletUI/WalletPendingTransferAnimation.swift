import Cocoa
import TGUIKit
import TelegramTheme
import SceneEffects

let walletPendingTransferTint = NSColor(rgb: 0x30a1f5)
private let walletPendingTransferLightTint = NSColor(rgb: 0x5cccff)
let walletPendingTransferSheenBands: [(width: CGFloat, peak: CGFloat, lineWidth: CGFloat)] = [(150.0, 0.07, 0.0), (60.0, 0.07, 0.0), (120.0, 0.22, 5.0), (90.0, 0.85, 1.2)]

struct WalletPendingTransferStar {
    let angle: Double
    let speed: Double
    let size: Double
    let life: Double
    let delay: Double
    let phase: Double
    let tone: Int
}

let walletPendingTransferStars: [WalletPendingTransferStar] = {
    var seed: UInt64 = 31 &* 0x9E37_79B9_7F4A_7C15 | 1
    func random(_ lower: Double, _ upper: Double) -> Double {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return lower + (upper - lower) * Double(seed % 1_000_000) / 1_000_000.0
    }
    return (0 ..< 34).map { i in
        return WalletPendingTransferStar(angle: i % 2 == 0 ? .pi + random(-0.75, 0.75) : random(0.0, 2.0 * .pi),
            speed: random(160.0, 760.0), size: random(2.6, 6.2), life: random(0.6, 1.15),
            delay: random(0.0, 0.09), phase: random(0.0, 2.0 * .pi), tone: Int(random(0.0, 2.99)))
    }
}()

private let walletPendingTransferStarImages: [CGImage] = [walletPendingTransferTint, walletPendingTransferLightTint, NSColor(rgb: 0x2178f7)].compactMap { color in
    return generateImage(NSMakeSize(48.0, 48.0), contextGenerator: { size, context in
        context.clear(NSMakeRect(0, 0, size.width, size.height))
        let center = NSMakePoint(size.width * 0.5, size.height * 0.5)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.withAlphaComponent(0.28).cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray, locations: [0.0, 1.0]) {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: 24.0, options: [])
        }
        let path = CGMutablePath()
        path.move(to: NSMakePoint(center.x + 15.0, center.y))
        for i in 1 ... 4 {
            let angle = CGFloat(i) * .pi / 2.0
            path.addQuadCurve(to: NSMakePoint(center.x + cos(angle) * 15.0, center.y + sin(angle) * 15.0),
                control: NSMakePoint(center.x + cos(angle - .pi / 4.0) * 2.7, center.y + sin(angle - .pi / 4.0) * 2.7))
        }
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    })
}

struct WalletPendingTransferMotion: Equatable {
    let reduced: Bool
    let elapsed: Double
    let finish: Double?
    let impact: Double
    let lift: CGFloat
    let dip: CGFloat
    let expansion: CGFloat
    let iconAlpha: CGFloat
    let iconScale: CGFloat
    let clockAlpha: CGFloat

    init(now: CFTimeInterval, start: CFTimeInterval, completion: CFTimeInterval?, landing: CFTimeInterval?, reduced: Bool) {
        let finish = completion.map { max(0.0, now - $0) }
        var lift = reduced ? CGFloat(0.0) : WalletPendingTransferMotion.spring(now - start)
        if let finish {
            lift *= 1.0 - WalletPendingTransferMotion.spring(finish, damping: 8.0, frequency: 13.0)
        }
        let impact = landing.map { now - $0 } ?? 0.0
        self.reduced = reduced
        self.elapsed = max(0.0, now - start)
        self.finish = finish
        self.impact = impact
        self.lift = lift
        self.dip = !reduced && impact > 0.0 && impact < 1.2 ? CGFloat(5.0 * sin(2.0 * .pi * 2.2 * impact) * exp(-impact / 0.2)) : 0.0
        self.expansion = reduced ? 0.0 : finish.map { CGFloat(pow(1.0 - min(1.0, $0 / 0.3), 3.0)) } ?? 1.0
        if reduced {
            self.iconAlpha = 1.0
        } else if let finish {
            self.iconAlpha = min(1.0, max(0.0, WalletPendingTransferMotion.spring(finish - 0.32, damping: 8.0, frequency: 17.0)))
        } else {
            self.iconAlpha = 0.0
        }
        self.iconScale = reduced ? 1.0 : finish.map { 0.2 + 0.8 * WalletPendingTransferMotion.spring($0 - 0.32, damping: 8.0, frequency: 17.0) } ?? 0.2
        self.clockAlpha = finish.map { 0.5 + 0.5 * CGFloat(cos(.pi * min(1.0, $0 / (reduced ? 0.15 : 0.35)))) } ?? 1.0
    }

    static func spring(_ time: Double, damping: Double = 7.0, frequency: Double = 14.0) -> CGFloat {
        guard time > 0.0 else {
            return 0.0
        }
        return CGFloat(1.0 - exp(-damping * time) * (cos(frequency * time) + damping / frequency * sin(frequency * time)))
    }

    var scale: CGFloat {
        return 1.0 + 0.035 * self.lift - 0.004 * self.dip
    }

    var translationY: CGFloat {
        return -2.0 * self.lift + self.dip
    }

    var surfaceOpacity: Float {
        return Float(max(0.0, min(1.0, self.lift)))
    }

    var showsSheen: Bool {
        return !self.reduced && self.finish == nil
    }

    var clockTime: Double {
        return self.reduced ? 0.0 : self.elapsed
    }

    var starTime: Double? {
        return self.reduced ? nil : self.finish
    }

    var diamondAlpha: CGFloat {
        return self.reduced ? 0.0 : self.finish.map { CGFloat(max(0.0, min(1.0, 1.0 - ($0 - 0.35) / 0.1))) } ?? 1.0
    }

    var finished: Bool {
        guard let finish = self.finish else {
            return false
        }
        return finish >= (self.reduced ? 0.15 : 1.3)
    }

    func slot(normal: CGPoint, pending: CGPoint) -> CGPoint {
        var slot = CGPoint(x: normal.x + (pending.x - normal.x) * self.expansion, y: normal.y + (pending.y - normal.y) * self.expansion)
        if let finish = self.finish, finish < 0.34 {
            slot.y -= CGFloat(sin(.pi * finish / 0.34)) * 11.0
        }
        return slot
    }

    func diamondWidth(iconWidth: CGFloat) -> CGFloat {
        var width: CGFloat = 34.0
        if let finish = self.finish {
            let pop = CGFloat(sin(.pi * min(1.0, finish / 0.26))) * 0.3
            let shrink = CGFloat(max(0.0, min(1.0, (finish - 0.18) / 0.16)))
            width = 34.0 * (1.0 + pop) * (1.0 - shrink) + iconWidth * shrink
        } else if self.impact > 0.0 && self.impact < 0.36 {
            width *= 1.0 + 0.26 * CGFloat(sin(.pi * self.impact / 0.36) * (1.0 - 0.3 * self.impact / 0.36))
        }
        return width
    }
}

enum WalletPendingTransferFlight {
    static func progress(now: CFTimeInterval, start: CFTimeInterval) -> CGFloat {
        return CGFloat(min(1.0, max(0.0, now - start) / 0.5))
    }

    static func center(origin: CGPoint, target: CGPoint, t: CGFloat) -> CGPoint {
        let d = target.y - origin.y
        let rise = 44.0 + max(0.0, -d)
        let b = -2.0 * rise - 2.0 * sqrt(max(0.0, rise * rise + rise * d))
        return CGPoint(x: origin.x + (target.x - origin.x) * t, y: origin.y + b * t + (d - b) * t * t)
    }

    static func width(sourceWidth: CGFloat, targetWidth: CGFloat, t: CGFloat) -> CGFloat {
        return (sourceWidth + (targetWidth - sourceWidth) * t) * (1.0 + 0.28 * sin(.pi * min(1.0, t / 0.75)))
    }

    static func rotationSpeed(t: CGFloat) -> Float {
        return Float(2.0 * .pi / 26.0 + (6.5 - 2.0 * .pi / 26.0) * min(1.0, t / 0.6))
    }
}

func walletPendingTransferSheen(elapsed: Double, size: CGSize, opacity: Float) -> (opacity: Float, bands: [(start: CGPoint, end: CGPoint)]?) {
    let u = (elapsed + 0.2).truncatingRemainder(dividingBy: 2.5) / 1.5
    let sheenOpacity = u <= 1.0 ? opacity * Float(sin(.pi * u)) : 0.0
    guard u <= 1.0, size.width > 0.0, size.height > 0.0 else {
        return (sheenOpacity, nil)
    }
    let x = (-0.25 + 1.5 * (0.5 - 0.5 * cos(.pi * u))) * size.width
    return (sheenOpacity, walletPendingTransferSheenBands.map { band in
        return (CGPoint(x: (x - band.width) / size.width, y: 0.0), CGPoint(x: (x + band.width) / size.width, y: band.width * 0.55 / size.height))
    })
}

func walletPendingTransferStarFrame(_ star: WalletPendingTransferStar, time: Double, origin: CGPoint) -> (position: CGPoint, opacity: Float, transform: CGAffineTransform)? {
    let age = time - star.delay
    guard age > 0.0 && age < star.life else {
        return nil
    }
    let u = age / star.life
    let distance = star.speed * (1.0 - exp(-2.6 * age)) / 2.6
    let scale = (0.55 + 0.45 * (1.0 - u)) * (0.72 + 0.28 * sin(age * 19.0 + star.phase))
    return (
        CGPoint(x: origin.x + cos(star.angle) * distance, y: origin.y + sin(star.angle) * distance * 0.45),
        Float(min(1.0, u / 0.12) * (1.0 - u * u)),
        CGAffineTransform(rotationAngle: star.phase + age * 2.4).scaledBy(x: scale, y: scale)
    )
}

func walletPendingTransferClockHandAngles(time: Double) -> (minute: CGFloat, hour: CGFloat) {
    return (CGFloat(time * 4.2), CGFloat(time * 4.2 / 12.0 - .pi / 2.0))
}

func walletPendingTransferAmountTransform(expansion: CGFloat, width: CGFloat, verticalOffset: CGFloat, isCollectible: Bool = false) -> (scale: CGFloat, translation: CGPoint) {
    let scale = 1.0 + 0.33 * expansion
    return (scale, CGPoint(x: (isCollectible ? -19.0 : -23.0) * expansion - (scale - 1.0) * width * 0.5, y: verticalOffset * expansion))
}

@available(macOS 10.15, *)
public final class WalletSendTransferAnimationSource {
    public let diamond: InteractiveDiamondView
    public weak var window: NSWindow?
    public let center: NSPoint
    public let width: CGFloat

    init(diamond: InteractiveDiamondView, window: NSWindow, center: NSPoint, width: CGFloat) {
        self.diamond = diamond
        self.window = window
        self.center = center
        self.width = width
    }

    static func capture(diamond: InteractiveDiamondView, width: CGFloat) -> WalletSendTransferAnimationSource? {
        guard let window = diamond.window else {
            return nil
        }
        let bounds = diamond.bounds
        let center = diamond.convert(NSMakePoint(bounds.midX, bounds.midY), to: nil)
        let left = diamond.convert(NSMakePoint(bounds.midX - width * 0.5, bounds.midY), to: nil)
        let right = diamond.convert(NSMakePoint(bounds.midX + width * 0.5, bounds.midY), to: nil)
        return WalletSendTransferAnimationSource(diamond: diamond, window: window, center: center, width: hypot(right.x - left.x, right.y - left.y))
    }
}

@available(macOS 10.15, *)
public typealias WalletSendTransferAnimation = (String, WalletSendTransferAnimationSource?) -> Bool

@available(macOS 10.15, *)
final class WalletPendingTransferAnimation: Equatable {
    let id: String
    private let isCollectible: Bool
    private let giftIcon = ImageView()
    var isPending = true
    var onFinished: (() -> Void)?
    private(set) var finished = false
    private(set) var start: CFTimeInterval?
    private(set) var completion: CFTimeInterval?
    private(set) var isVisible = false
    private weak var row: WalletTransactionRowView?
    private var link: SharedDisplayLinkDriver.Link?
    private let underlay = CALayer()
    private let underlayMask = CAShapeLayer()
    private let surface = CALayer()
    private let sheen = CALayer()
    private let particles = CALayer()
    private var bands: [CAGradientLayer] = []
    private var starLayers: [CALayer] = []
    private var savedMask: CALayer?
    private var savedMasksToBounds = false
    #if arch(arm64)
    private var diamond: InteractiveDiamondView?
    #endif
    private var flightSource: WalletSendTransferAnimationSource?
    private var flightOverlay: View?
    private var flightStart: CFTimeInterval?
    private var landing: CFTimeInterval?

    var isFlying: Bool {
        return self.flightSource != nil
    }

    init(id: String, isCollectible: Bool = false) {
        self.id = id
        self.isCollectible = isCollectible
        self.giftIcon.isEventLess = true
        self.giftIcon.isAccessibilityDecorative = true
        self.underlay.mask = self.underlayMask
        self.surface.cornerRadius = 22.0
        self.surface.shadowColor = NSColor.black.cgColor
        self.surface.shadowRadius = 14.0
        self.surface.shadowOffset = CGSize(width: 0.0, height: 6.0)
        self.particles.masksToBounds = true
        self.particles.cornerRadius = 22.0
        for (index, specification) in walletPendingTransferSheenBands.enumerated() {
            let band = CAGradientLayer()
            let color = index % 2 == 0 ? walletPendingTransferLightTint : walletPendingTransferTint
            let peak = specification.peak
            band.colors = [0.0, peak * 0.35, peak, peak * 0.35, 0.0].map { color.withAlphaComponent($0).cgColor }
            band.locations = [0.0, 0.3, 0.5, 0.7, 1.0]
            let mask = CAShapeLayer()
            mask.lineWidth = specification.lineWidth
            mask.fillColor = specification.lineWidth == 0.0 ? NSColor.black.cgColor : nil
            mask.strokeColor = specification.lineWidth == 0.0 ? nil : NSColor.black.cgColor
            band.mask = mask
            self.sheen.addSublayer(band)
            self.bands.append(band)
        }
    }

    deinit {
        self.link?.invalidate()
        self.detach()
        self.flightOverlay?.removeFromSuperview()
        #if arch(arm64)
        self.diamond?.isRenderingEnabled = false
        #endif
    }

    static func ==(lhs: WalletPendingTransferAnimation, rhs: WalletPendingTransferAnimation) -> Bool {
        return lhs === rhs
    }

    func bind(row: WalletTransactionRowView) {
        if self.row !== row {
            self.detach()
            self.row = row
            self.attach(row)
        }
        self.updateLink()
    }

    func unbind(row: WalletTransactionRowView) {
        guard self.row === row else {
            return
        }
        self.detach()
        self.row = nil
        self.updateLink()
    }

    func launch(_ source: WalletSendTransferAnimationSource, at now: CFTimeInterval) {
        guard let contentView = source.window?.contentView else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        #if arch(arm64)
        self.diamond?.removeFromSuperview()
        self.diamond?.isRenderingEnabled = false
        self.diamond = source.diamond
        #endif
        let overlay = View(frame: contentView.bounds)
        overlay.userInteractionEnabled = false
        overlay.autoresizingMask = [.width, .height]
        overlay.layer?.masksToBounds = false
        contentView.addSubview(overlay)
        overlay.addSubview(source.diamond)
        let center = overlay.convert(source.center, from: nil)
        source.diamond.setFrameOrigin(NSMakePoint(center.x - source.diamond.frame.width / 2.0, center.y - source.diamond.frame.height / 2.0))
        source.diamond.updateWalletTransfer(width: source.width, rotationSpeed: 2.0 * .pi / 26.0, completion: false, isDark: theme.colors.isDark)
        source.diamond.isRenderingEnabled = true
        self.flightOverlay = overlay
        self.flightSource = source
        self.flightStart = now
        self.start = now + 0.1
        CATransaction.commit()
        self.updateLink()
    }

    private func waitForFlightLayout(at time: CFTimeInterval) {
        guard let flightStart = self.flightStart, time - flightStart < 0.5 else {
            self.suspend()
            self.updateLink()
            return
        }
    }

    func updateLink() {
        let active = (self.row?.window != nil || self.isFlying) && !self.finished
        if active {
            if self.link == nil {
                self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    self?.update(at: CACurrentMediaTime())
                })
            }
            self.update(at: CACurrentMediaTime())
        } else {
            self.link?.invalidate()
            self.link = nil
            self.suspend()
        }
    }

    private func attach(_ row: WalletTransactionRowView) {
        guard let container = row.containerView.layer else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        row.layer?.masksToBounds = false
        self.savedMask = container.mask
        self.savedMasksToBounds = container.masksToBounds
        container.mask = nil
        container.masksToBounds = false
        container.insertSublayer(self.underlay, at: 0)
        container.insertSublayer(self.surface, above: self.underlay)
        container.addSublayer(self.sheen)
        container.addSublayer(self.particles)
        if self.isCollectible {
            self.giftIcon.image = NSImage(named: "Wallet_TransactionCollectibleLarge")?.precomposed(theme.colors.grayText)
            self.giftIcon.sizeToFit()
            row.containerView.addSubview(self.giftIcon)
        }
        #if arch(arm64)
        if !self.isCollectible && self.diamond == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let diamond = InteractiveDiamondView(frame: NSMakeRect(0, 0, 150, 150))
            diamond.update(size: NSMakeSize(150, 150), diamondWidth: 34.0, isVisible: false, lightBackground: !theme.colors.isDark)
            diamond.prepareForWalletTransfer()
            self.diamond = diamond
        }
        if !self.isFlying, let diamond = self.diamond {
            row.containerView.addSubview(diamond)
        }
        #endif
        CATransaction.commit()
    }

    private func detach() {
        guard let row = self.row else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        row.borderView.opacity = 1.0
        row.layer?.masksToBounds = true
        row.layer?.zPosition = 0.0
        if let container = row.containerView.layer {
            container.sublayerTransform = CATransform3DIdentity
            container.masksToBounds = self.savedMasksToBounds
            if let savedMask = self.savedMask {
                container.mask = savedMask
            }
        }
        self.savedMask = nil
        self.underlay.removeFromSuperlayer()
        self.surface.removeFromSuperlayer()
        self.sheen.removeFromSuperlayer()
        self.particles.removeFromSuperlayer()
        self.giftIcon.removeFromSuperview()
        #if arch(arm64)
        if !self.isFlying {
            self.diamond?.removeFromSuperview()
        }
        #endif
        CATransaction.commit()
        row.resetTransferPresentation()
    }

    func suspend() {
        self.isVisible = false
        #if arch(arm64)
        self.diamond?.isRenderingEnabled = false
        #endif
        if self.isFlying {
            self.flightSource = nil
            self.flightStart = nil
            self.flightOverlay?.removeFromSuperview()
            self.flightOverlay = nil
            #if arch(arm64)
            self.diamond?.removeFromSuperview()
            #endif
            self.landing = nil
        }
        if !self.isPending {
            self.finish()
        }
    }

    private func finish() {
        guard !self.finished else {
            return
        }
        self.finished = true
        self.link?.invalidate()
        self.link = nil
        self.onFinished?()
    }

    private func update(at now: CFTimeInterval) {
        guard let row = self.row, row.window != nil else {
            if self.isFlying {
                self.waitForFlightLayout(at: now)
            } else {
                self.suspend()
            }
            return
        }
        self.isVisible = true
        if self.start == nil {
            guard self.isPending else {
                self.finish()
                return
            }
            self.start = now
        }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduced && self.isFlying {
            self.suspend()
            self.isVisible = true
        }
        if !self.isPending && self.completion == nil && !self.isFlying {
            self.completion = now
        }
        let motion = WalletPendingTransferMotion(now: now, start: self.start ?? now, completion: self.completion, landing: self.landing, reduced: reduced)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let container = row.containerView
        let lift = CATransform3DScale(CATransform3DMakeTranslation(0.0, motion.translationY, 0.0), motion.scale, motion.scale, 1.0)
        self.underlay.bounds = container.bounds
        self.underlay.position = NSMakePoint(container.bounds.midX, container.bounds.midY)
        self.underlay.transform = CATransform3DInvert(lift)
        self.underlay.backgroundColor = row.backdorColor.cgColor
        self.underlayMask.frame = self.underlay.bounds
        self.underlayMask.path = (self.savedMask as? CAShapeLayer)?.path
        if let layer = container.layer {
            layer.sublayerTransform = walletAmountCenteredTransform(lift, layer: layer)
        }
        row.layer?.zPosition = 1.0
        self.surface.frame = container.bounds
        self.surface.shadowPath = CGPath(roundedRect: container.bounds, cornerWidth: 22.0, cornerHeight: 22.0, transform: nil)
        self.surface.backgroundColor = row.backdorColor.cgColor
        self.surface.opacity = motion.surfaceOpacity
        self.surface.shadowOpacity = 0.13
        self.updateSheen(bounds: container.bounds, elapsed: motion.elapsed, opacity: motion.showsSheen ? 1.0 : 0.0)
        row.borderView.opacity = Float(1.0 - motion.clockAlpha)
        #if arch(arm64)
        let animatesIcon = true
        #else
        let animatesIcon = self.isCollectible
        #endif
        row.applyTransferPresentation(expansion: animatesIcon ? motion.expansion : 0, iconAlpha: animatesIcon ? motion.iconAlpha : 1, iconScale: animatesIcon ? motion.iconScale : 1, clockAlpha: motion.clockAlpha, time: motion.clockTime)
        let icon = row.transferIconFrame
        let amount = row.transferAmountFrame
        let pending = self.isCollectible ? NSMakePoint(amount.maxX + 2 + giftIcon.frame.width / 2, amount.midY) : NSMakePoint(container.bounds.width - row.transferRightInset - 18.5, container.bounds.height * 0.5)
        let slot = motion.slot(normal: NSMakePoint(icon.midX, icon.midY), pending: pending)
        #if arch(arm64)
        if let source = self.flightSource, let flightStart = self.flightStart, let overlay = self.flightOverlay, let diamond = self.diamond {
            let t = WalletPendingTransferFlight.progress(now: now, start: flightStart)
            let origin = overlay.convert(source.center, from: nil)
            let target = overlay.convert(slot, from: container)
            let center = WalletPendingTransferFlight.center(origin: origin, target: target, t: t)
            diamond.setFrameOrigin(NSMakePoint(center.x - diamond.frame.width / 2.0, center.y - diamond.frame.height / 2.0))
            let edge = overlay.convert(NSMakePoint(slot.x + 34.0, slot.y), from: container)
            let targetWidth = hypot(edge.x - target.x, edge.y - target.y)
            diamond.updateWalletTransfer(width: WalletPendingTransferFlight.width(sourceWidth: source.width, targetWidth: targetWidth, t: t), rotationSpeed: WalletPendingTransferFlight.rotationSpeed(t: t), completion: false, isDark: theme.colors.isDark)
            diamond.isRenderingEnabled = !reduced
            if t >= 1.0 || reduced {
                self.flightSource = nil
                self.flightStart = nil
                container.addSubview(diamond)
                diamond.setFrameOrigin(NSMakePoint(slot.x - diamond.frame.width / 2.0, slot.y - diamond.frame.height / 2.0))
                diamond.updateWalletTransfer(width: 34.0, rotationSpeed: 6.5, completion: false, isDark: theme.colors.isDark)
                self.flightOverlay?.removeFromSuperview()
                self.flightOverlay = nil
                self.landing = now
                diamond.spin(7.0, decay: 0.7)
            }
        } else if let diamond = self.diamond {
            if diamond.superview !== container {
                container.addSubview(diamond)
            }
            diamond.setFrameOrigin(NSMakePoint(slot.x - diamond.frame.width / 2.0, slot.y - diamond.frame.height / 2.0))
            diamond.alphaValue = motion.diamondAlpha
            diamond.updateWalletTransfer(width: motion.diamondWidth(iconWidth: icon.width), rotationSpeed: 6.5, completion: motion.finish != nil, isDark: theme.colors.isDark)
            diamond.isRenderingEnabled = !reduced && diamond.alphaValue > 0.0
        }
        #endif
        if self.isCollectible {
            let scale: CGFloat
            if let finish = motion.finish {
                let pop = CGFloat(sin(.pi * min(1, finish / 0.26))) * 0.3
                let shrink = CGFloat(max(0, min(1, (finish - 0.18) / 0.16)))
                scale = (1 + pop) * (1 - shrink) + icon.width / max(1, giftIcon.frame.width) * shrink
            } else {
                scale = reduced ? 1 : 1 + 0.08 * CGFloat(sin(2 * .pi * motion.elapsed / 1.1))
            }
            giftIcon.setFrameOrigin(NSMakePoint(slot.x - giftIcon.frame.width / 2, slot.y - giftIcon.frame.height / 2))
            if let layer = giftIcon.layer {
                layer.transform = walletAmountCenteredTransform(CATransform3DMakeScale(max(0.001, scale), max(0.001, scale), 1), layer: layer)
            }
            giftIcon.alphaValue = reduced ? 0 : motion.finish.map { CGFloat(max(0, min(1, 1 - ($0 - 0.35) / 0.1))) } ?? 1
        }
        if animatesIcon {
            self.updateStars(bounds: container.bounds, time: motion.starTime, origin: pending)
        }
        CATransaction.commit()
        if motion.finished {
            self.finish()
        }
    }

    private func updateStars(bounds: CGRect, time: Double?, origin: CGPoint) {
        guard let time, time < 1.25 else {
            self.particles.isHidden = true
            return
        }
        self.particles.isHidden = false
        self.particles.frame = bounds
        if self.starLayers.isEmpty {
            for star in walletPendingTransferStars {
                let layer = CALayer()
                layer.contents = walletPendingTransferStarImages.indices.contains(star.tone) ? walletPendingTransferStarImages[star.tone] : nil
                layer.bounds = CGRect(x: 0.0, y: 0.0, width: star.size * 4.8, height: star.size * 4.8)
                self.particles.addSublayer(layer)
                self.starLayers.append(layer)
            }
        }
        for (star, layer) in zip(walletPendingTransferStars, self.starLayers) {
            guard let frame = walletPendingTransferStarFrame(star, time: time, origin: origin) else {
                layer.opacity = 0.0
                continue
            }
            layer.position = frame.position
            layer.opacity = frame.opacity
            layer.setAffineTransform(frame.transform)
        }
    }

    private func updateSheen(bounds: CGRect, elapsed: Double, opacity: Float) {
        if self.sheen.frame != bounds {
            self.sheen.frame = bounds
            let path = CGPath(roundedRect: bounds, cornerWidth: 22.0, cornerHeight: 22.0, transform: nil)
            for band in self.bands {
                band.frame = bounds
                (band.mask as? CAShapeLayer)?.path = path
            }
        }
        let sheen = walletPendingTransferSheen(elapsed: elapsed, size: bounds.size, opacity: opacity)
        self.sheen.opacity = sheen.opacity
        guard let points = sheen.bands else {
            return
        }
        for (band, point) in zip(self.bands, points) {
            band.startPoint = point.start
            band.endPoint = point.end
        }
    }
}
