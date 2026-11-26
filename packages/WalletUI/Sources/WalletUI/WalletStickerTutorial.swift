import Cocoa
import Vision
import TGUIKit
import TelegramContext
import Localization
import WalletContext

@available(macOS 10.15, *)
final class WalletStickerTutorial {
    private let context: any AccountContextProtocol
    private let environment: WalletUIEnvironment
    private weak var card: WalletCardView?
    private weak var grid: WalletCollectablesGrid?
    private var sticker: WalletContext.CardSticker?
    private var startedAt: CFTimeInterval = 0
    private var animator: ConstantDisplayLinkAnimator?
    private var carrying = false
    private var scheduled = false
    private var visible = false
    private var shown = false
    private var tip: WalletStickerTutorialTip?

    private var noticeKey: String {
        return "wallet.cardStickersTutorial.\(context.peerId.toInt64())"
    }

    init(context: any AccountContextProtocol, environment: WalletUIEnvironment) {
        self.context = context
        self.environment = environment
    }

    func updateVisibility(_ visible: Bool) {
        self.visible = visible
        if !visible { end() }
    }

    func start(card: WalletCardView, grid: WalletCollectablesGrid, gift: WalletContext.Collectible, spot: WalletStickerPlacement.Spot, canStart: @escaping () -> Bool) {
        guard visible, !shown, !scheduled, sticker == nil, !UserDefaults.standard.bool(forKey: noticeKey),
              WalletCollectableImages.art(gift.address) != nil else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self, weak card, weak grid] in
            guard let self else { return }
            self.scheduled = false
            guard self.visible, canStart(), let card, let grid, grid.isShown, card.acceptsStickers,
                  grid.visibleGiftIds.contains(gift.address) else { return }
            self.shown = true
            UserDefaults.standard.set(true, forKey: self.noticeKey)
            self.card = card
            self.grid = grid
            self.startedAt = CACurrentMediaTime()
            let size = card.stickerSurfaceSize
            self.sticker = WalletContext.CardSticker(gift: gift, x: Double(spot.center.x / max(1, size.width)), y: Double(spot.center.y / max(1, size.height)), angle: 0, scale: Double(spot.scale), modelFile: nil, geometryVersion: 1)
            self.showTip(onCard: false)
            if let image = WalletCollectableImages.art(gift.address) {
                walletStickerOutline(image) { [weak self] path in
                    guard let self, let sticker = self.sticker, sticker.gift.address == gift.address, let path else { return }
                    self.card?.setStickerHint(sticker, outline: path)
                }
            }
            self.animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] _ in
                self?.tick()
            })
            self.animator?.isPaused = false
        }
    }

    func picked(_ id: String) {
        guard sticker?.gift.address == id else { return }
        carrying = true
        grid?.setModelWiggle(id, angle: 0, scale: 1)
        showTip(onCard: true)
    }

    func finish() {
        guard sticker != nil else { return }
        end()
        let text = strings().walletStickerTutorialDone
        environment.showModalText(for: context.window, text: text)
    }

    func end() {
        if let sticker {
            grid?.setModelWiggle(sticker.gift.address, angle: 0, scale: 1)
        }
        card?.setStickerHint(nil, outline: nil)
        tip?.removeFromSuperview()
        tip = nil
        sticker = nil
        carrying = false
        animator?.isPaused = true
        animator = nil
    }

    private func showTip(onCard: Bool) {
        let text = onCard ? strings().walletStickerTutorialCard : strings().walletStickerTutorialTile
        tip?.removeFromSuperview()
        let tip = WalletStickerTutorialTip(text: text)
        self.tip = tip
        card?.window?.contentView?.addSubview(tip)
        positionTip()
    }

    private func positionTip() {
        guard let sticker, let tip, let parent = tip.superview else { return }
        let target: NSRect
        if carrying, let card {
            target = parent.convert(NSMakeRect(card.stickerCenter(sticker).x - 1, card.stickerCenter(sticker).y - card.stickerSide(sticker) / 2, 2, 2), from: card)
        } else if let grid, let rect = grid.tileFrame(sticker.gift.address) {
            target = parent.convert(rect, from: grid)
        } else {
            return
        }
        let x = max(12, min(parent.bounds.width - tip.frame.width - 12, target.midX - tip.frame.width / 2))
        tip.setFrameOrigin(NSMakePoint(x, max(12, target.minY - tip.frame.height - 6)))
        tip.arrowX = target.midX - x
        tip.needsLayout = true
    }

    private func tick() {
        guard let sticker, grid?.isShown == true, card?.window != nil else {
            end()
            return
        }
        positionTip()
        guard !carrying else { return }
        let u = (CACurrentMediaTime() - startedAt - 0.5).truncatingRemainder(dividingBy: 2.2)
        var angle: CGFloat = 0
        var scale: CGFloat = 1
        if u > 0, u < 0.8, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let p = CGFloat(u / 0.8)
            angle = 0.16 * sin(p * 3 * .pi) * (1 - p)
            scale = 1 + 0.08 * sin(p * .pi)
        }
        grid?.setModelWiggle(sticker.gift.address, angle: angle, scale: scale)
    }

    deinit {
        animator?.isPaused = true
    }
}

private final class WalletStickerTutorialTip: View {
    private let body = View()
    private let textView = TextView()
    private let arrow = CAShapeLayer()
    var arrowX: CGFloat = 0

    init(text: String) {
        let layout = TextViewLayout(.initialize(string: text, color: .white, font: .medium(.text)), alignment: .center)
        layout.measure(width: 240)
        super.init(frame: NSMakeRect(0, 0, layout.layoutSize.width + 24, layout.layoutSize.height + 24))
        isEventLess = true
        body.isEventLess = true
        body.backgroundColor = NSColor.black.withAlphaComponent(0.9)
        body.layer?.cornerRadius = 12
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.update(layout)
        body.addSubview(textView)
        addSubview(body)
        arrow.fillColor = NSColor.black.withAlphaComponent(0.9).cgColor
        layer?.addSublayer(arrow)
    }

    required init(frame frameRect: NSRect) { fatalError("init(frame:) has not been implemented") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        body.frame = bounds.insetBy(dx: 0, dy: 0)
        body.setFrameSize(NSMakeSize(bounds.width, bounds.height - 6))
        textView.setFrameOrigin(NSMakePoint(12, 9))
        let x = min(bounds.width - 16, max(16, arrowX))
        let path = CGMutablePath()
        path.move(to: NSMakePoint(x - 6, bounds.height - 6))
        path.addLine(to: NSMakePoint(x, bounds.height))
        path.addLine(to: NSMakePoint(x + 6, bounds.height - 6))
        path.closeSubpath()
        arrow.path = path
    }
}

private func walletStickerOutline(_ image: CGImage, completion: @escaping (CGPath?) -> Void) {
    guard #available(macOS 11.0, *) else {
        completion(CGPath(ellipseIn: CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84), transform: nil))
        return
    }
    DispatchQueue.global(qos: .userInitiated).async {
        let side = 256
        var path: CGPath?
        if let maskContext = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) {
            maskContext.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            if let mask = maskContext.makeImage(), let gray = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                let bounds = CGRect(x: 0, y: 0, width: side, height: side)
                gray.setFillColor(gray: 0, alpha: 1)
                gray.fill(bounds)
                gray.clip(to: bounds, mask: mask)
                gray.setFillColor(gray: 1, alpha: 1)
                gray.fill(bounds)
                if let silhouette = gray.makeImage() {
                    let request = VNDetectContoursRequest()
                    request.detectsDarkOnLight = false
                    request.maximumImageDimension = side
                    try? VNImageRequestHandler(cgImage: silhouette, options: [:]).perform([request])
                    if let outer = request.results?.first?.topLevelContours.max(by: { lhs, rhs in
                        let a = lhs.normalizedPath.boundingBox
                        let b = rhs.normalizedPath.boundingBox
                        return a.width * a.height < b.width * b.height
                    }) {
                        let smooth = (try? outer.polygonApproximation(epsilon: 0.003)) ?? outer
                        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
                        path = smooth.normalizedPath.copy(using: &flip)
                    }
                }
            }
        }
        DispatchQueue.main.async { completion(path) }
    }
}
