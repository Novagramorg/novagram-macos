import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import Postbox
import SwiftSignalKit
import InlineStickerLayer
import UniqueGiftBackground

public final class CraftGiftLayer: SimpleLayer, CubeMountableLayer {
    private let giftBackgroundLayer = UniqueGiftBackgroundLayer()
    private var stickerLayer: InlineStickerItemLayer?
    private let rarityBadge = SimpleLayer()
    private let rarityLabel = CATextLayer()
    private let removeButton = SimpleLayer()

    private weak var context: (any AccountContextProtocol)?
    private let size: CGFloat
    private var showRemoveButton: Bool = false
    

    public init(size: CGFloat) {
        self.size = size
        super.init()

        self.frame = CGRect(x: 0, y: 0, width: size, height: size)
        self.cornerRadius = size * 0.25
        self.masksToBounds = false

        giftBackgroundLayer.frame = bounds
        addSublayer(giftBackgroundLayer)

        rarityBadge.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
        rarityBadge.cornerRadius = 8
        rarityBadge.isHidden = true
        addSublayer(rarityBadge)

        rarityLabel.font = NSFont.boldSystemFont(ofSize: 9)
        rarityLabel.fontSize = 9
        rarityLabel.foregroundColor = NSColor.white.cgColor
        rarityLabel.alignmentMode = .center
        rarityLabel.contentsScale = System.backingScale
        rarityBadge.addSublayer(rarityLabel)

        let removeSize: CGFloat = 16
        removeButton.frame = CGRect(x: -2, y: -4, width: removeSize, height: removeSize)
        removeButton.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
        removeButton.cornerRadius = removeSize / 2
        removeButton.isHidden = true

        let dismissIcon = generateImage(NSMakeSize(removeSize, removeSize), contextGenerator: { size, ctx in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.66)
            ctx.setLineCap(.round)
            let inset: CGFloat = 5
            ctx.move(to: CGPoint(x: inset, y: inset))
            ctx.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            ctx.move(to: CGPoint(x: size.width - inset, y: inset))
            ctx.addLine(to: CGPoint(x: inset, y: size.height - inset))
            ctx.strokePath()
        })
        let closeIconLayer = SimpleLayer()
        closeIconLayer.contents = dismissIcon
        closeIconLayer.contentsGravity = .center
        closeIconLayer.frame = CGRect(x: 0, y: 0, width: removeSize, height: removeSize)
        removeButton.addSublayer(closeIconLayer)
        addSublayer(removeButton)
        
    }

    public override init(layer: Any) {
        self.size = 70
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(gift: ProfileGiftsContext.State.StarGift, context: any AccountContextProtocol, superview: NSView?) {
        self.context = context

        guard let unique = gift.gift.unique else { return }

        giftBackgroundLayer.frame = bounds
        if let content = UniqueGiftBackgroundContent(gift: unique) {
            giftBackgroundLayer.isHidden = false
            giftBackgroundLayer.update(context: context, content: content, style: .item(giftCenterY: size / 2, cornerRadius: size * 0.25))
        } else {
            giftBackgroundLayer.isHidden = true
        }

        let stickerSize = size * 0.5
        if let file = unique.file {
            if stickerLayer == nil {
                let layer = InlineStickerItemLayer(
                    account: context.account,
                    file: file,
                    size: NSMakeSize(stickerSize, stickerSize),
                    playPolicy: .loop
                )
                layer.isPlayable = true
                layer.superview = superview
                addSublayer(layer)
                stickerLayer = layer
            }
            stickerLayer?.frame = CGRect(
                x: (size - stickerSize) / 2,
                y: (size - stickerSize) / 2,
                width: stickerSize,
                height: stickerSize
            )
        }

        updateRarityBadge(unique: unique)
    }

    private func updateRarityBadge(unique: StarGift.UniqueGift) {
        let chancePercent = (unique.craftChancePermille ?? 0) / 10
        guard chancePercent > 0 else {
            rarityBadge.isHidden = true
            return
        }

        rarityBadge.isHidden = false
        rarityLabel.string = "+\(chancePercent)%"

        let textSize = rarityLabel.preferredFrameSize()
        let badgeWidth = textSize.width + 8
        let badgeHeight: CGFloat = 16

        rarityBadge.frame = CGRect(
            x: size - badgeWidth + 4,
            y: -4,
            width: badgeWidth,
            height: badgeHeight
        )
        var rect = rarityBadge.bounds.focus(textSize)
        rect.origin.y -= 1
        rarityLabel.frame = rect
    }

    public func setShowRemoveButton(_ show: Bool) {
        showRemoveButton = show
        removeButton.isHidden = !show
    }

    public func setOnCube(_ onCube: Bool) {
        rarityBadge.isHidden = onCube || (rarityLabel.string as? String)?.isEmpty != false
        removeButton.isHidden = onCube || !showRemoveButton
    }
}

public final class CraftResultLayer: SimpleLayer {
    private let backgroundLayer = SimpleLayer()
    private let progressRingLayer = CAShapeLayer()
    private let progressTrackLayer = CAShapeLayer()
    private var iconLayer: SimpleLayer?
    private let percentLabel = CATextLayer()

    private var currentProgress: CGFloat = 0
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
        super.init()

        self.frame = CGRect(x: 0, y: 0, width: size, height: size)
        self.cornerRadius = size * 0.28
        self.masksToBounds = true
        self.borderWidth = 1
        self.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        addSublayer(backgroundLayer)

        progressTrackLayer.fillColor = nil
        progressTrackLayer.strokeColor = NSColor.white.withAlphaComponent(0.15).cgColor
        progressTrackLayer.lineWidth = 4
        progressTrackLayer.lineCap = .round
        addSublayer(progressTrackLayer)

        progressRingLayer.fillColor = nil
        progressRingLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        progressRingLayer.lineWidth = 4
        progressRingLayer.lineCap = .round
        progressRingLayer.strokeEnd = 0
        addSublayer(progressRingLayer)

        percentLabel.font = NSFont.medium(.text)
        percentLabel.fontSize = 13
        percentLabel.foregroundColor = NSColor.white.cgColor
        percentLabel.alignmentMode = .center
        percentLabel.contentsScale = System.backingScale
        addSublayer(percentLabel)

        let anvilImage = NSImage(resource: .iconCraftAnvil).precomposed(.white, zoom: 0.8)
        let icon = SimpleLayer()
        icon.contents = anvilImage
        icon.contentsGravity = .center
        icon.frame = CGRect(x: 0, y: 0, width: anvilImage.size.width, height: anvilImage.size.height)
        addSublayer(icon)
        iconLayer = icon

        updateLayout()
    }

    public override init(layer: Any) {
        self.size = 90
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(progress: Int, backgroundColor: NSColor, animated: Bool) {
        let progressValue = CGFloat(progress) / 100.0

        self.backgroundColor = backgroundColor.cgColor
        backgroundLayer.backgroundColor = backgroundColor.withAlphaComponent(0.6).cgColor
        percentLabel.string = "\(progress)%"

        if animated && currentProgress != progressValue {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = currentProgress
            animation.toValue = progressValue
            animation.duration = 0.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressRingLayer.add(animation, forKey: "progressAnimation")
        }

        currentProgress = progressValue
        progressRingLayer.strokeEnd = progressValue

        updateLayout()
    }

    private func updateLayout() {
        backgroundLayer.frame = bounds

        let ringInset: CGFloat = 12
        let ringRadius = (min(bounds.width, bounds.height) - ringInset * 2) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let gapAngle: CGFloat = CGFloat.pi * 0.45
        let bottomAngle: CGFloat = CGFloat.pi * 0.5
        let startAngle = bottomAngle + gapAngle / 2
        let endAngle = bottomAngle - gapAngle / 2 + CGFloat.pi * 2

        let ringPath = CGMutablePath()
        ringPath.addArc(center: center, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)

        progressTrackLayer.path = ringPath
        progressTrackLayer.frame = bounds

        progressRingLayer.path = ringPath
        progressRingLayer.frame = bounds

        if let iconLayer = iconLayer {
            iconLayer.position = CGPoint(x: center.x + 3, y: center.y - 8)
        }

        let textSize = percentLabel.preferredFrameSize()
        percentLabel.frame = CGRect(
            x: (bounds.width - textSize.width) / 2,
            y: bounds.height - textSize.height - 8,
            width: textSize.width,
            height: textSize.height
        )
    }

    public override func layoutSublayers() {
        super.layoutSublayers()
        updateLayout()
    }
}

public final class CraftSideFaceLayer: SimpleLayer {
    private let backgroundLayer = SimpleLayer()
    private var iconLayer: SimpleLayer?
    private let countLabel = CATextLayer()

    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
        super.init()

        self.frame = CGRect(x: 0, y: 0, width: size, height: size)
        self.cornerRadius = size * 0.28
        self.masksToBounds = true
        self.borderWidth = 1
        self.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        addSublayer(backgroundLayer)

        let brokenImage = NSImage(resource: .iconCraftGiftBroken).precomposed(.white.withAlphaComponent(1))
        let icon = SimpleLayer()
        icon.contents = brokenImage
        icon.contentsGravity = .center
        icon.frame = CGRect(x: 0, y: 0, width: brokenImage.size.width, height: brokenImage.size.height)
        addSublayer(icon)
        iconLayer = icon

        countLabel.font = NSFont.medium(.text)
        countLabel.fontSize = 13
        countLabel.foregroundColor = NSColor.white.cgColor
        countLabel.alignmentMode = .center
        countLabel.contentsScale = System.backingScale
        addSublayer(countLabel)

        updateLayout()
    }

    public override init(layer: Any) {
        self.size = 90
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(giftCount: Int, backgroundColor: NSColor, animated: Bool = false) {
        countLabel.string = "×\(giftCount)"
        updateLayout()

        if animated {
            let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
            colorAnimation.fromValue = self.backgroundColor
            colorAnimation.toValue = backgroundColor.cgColor
            colorAnimation.duration = 0.3
            colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.add(colorAnimation, forKey: "backgroundColorAnimation")
            backgroundLayer.add(colorAnimation, forKey: "backgroundColorAnimation")
        }

        self.backgroundColor = backgroundColor.cgColor
        backgroundLayer.backgroundColor = backgroundColor.cgColor
    }

    private func updateLayout() {
        backgroundLayer.frame = bounds

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        if let iconLayer = iconLayer {
            iconLayer.position = CGPoint(x: center.x, y: center.y - 8)
        }

        let textSize = countLabel.preferredFrameSize()
        countLabel.frame = CGRect(
            x: (bounds.width - textSize.width) / 2,
            y: bounds.height - textSize.height - 10,
            width: textSize.width,
            height: textSize.height
        )
    }

    public override func layoutSublayers() {
        super.layoutSublayers()
        updateLayout()
    }
}

public final class EmptySlotLayer: SimpleLayer {
    private let dashedBorder = CAShapeLayer()
    private let plusLayer = SimpleLayer()

    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
        super.init()

        self.frame = CGRect(x: 0, y: 0, width: size, height: size)
        self.cornerRadius = 14
        self.masksToBounds = false

        dashedBorder.strokeColor = NSColor.white.withAlphaComponent(0.3).cgColor
        dashedBorder.fillColor = nil
        dashedBorder.lineDashPattern = [6, 4]
        dashedBorder.lineWidth = 1.5
        addSublayer(dashedBorder)

        let plusImage = NSImage(resource: .iconCraftAddSlot).precomposed(.white.withAlphaComponent(0.5))
        plusLayer.contents = plusImage
        plusLayer.contentsGravity = .center
        plusLayer.frame = CGRect(
            x: (size - plusImage.size.width) / 2,
            y: (size - plusImage.size.height) / 2,
            width: plusImage.size.width,
            height: plusImage.size.height
        )
        addSublayer(plusLayer)

        updateLayout()
        
    }

    public override init(layer: Any) {
        self.size = 70
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateLayout() {
        let path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 14, cornerHeight: 14, transform: nil)
        dashedBorder.path = path
        dashedBorder.frame = bounds
    }
}
