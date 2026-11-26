import Cocoa
import Foundation
import TGUIKit
import UniqueGiftBackground
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import TelegramMediaUtils
import LokiRng
import InlineStickerLayer
import CubeUI
import StarsUI

public final class CraftAnvilPatternView: View {
    private let patternContainer = SimpleLayer()
    private var patternLayers: [SimpleLayer] = []
    private var patternImage: CGImage?
    private var patternColor: NSColor = .white

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(patternContainer)
        layer?.masksToBounds = false
        patternContainer.masksToBounds = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func set(color: NSColor, animated: Bool) {
        self.patternColor = color
        self.patternImage = TelegramThemeHooks.shared.image(.iconNftAnvil).precomposed(color)
        updatePatternImages()
        updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }

    public var fraction: CGFloat = 1 {
        didSet {
            updateLayout(size: frame.size, transition: .immediate)
        }
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        patternContainer.frame = NSMakeRect(size.width / 2, size.height / 2, size.width, size.height)

        var layerIndex = 0
        let lokiRng = LokiRng(seed0: 456, seed1: 0, seed2: 0)

        for row in 0 ..< 3 {
            let patternCount = row % 2 == 0 ? 7 : 6
            let angleSpan = CGFloat.pi * 2.0 / CGFloat(patternCount)

            for i in 0 ..< patternCount {
                let baseDistance: CGFloat = 55 + CGFloat(row) * 32.0

                let distanceFraction = max(0.0, min(1.0, baseDistance / 120.0))
                let scaleFraction = patternScaleValueAt(fraction: fraction, t: distanceFraction, reverse: false)
                let distance = baseDistance * (1.0 - scaleFraction) + 15.0 * scaleFraction

                var angle = -CGFloat.pi * 0.5 + CGFloat(i) * angleSpan
                if row % 2 != 0 {
                    angle += angleSpan * 0.5
                }
                let position = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)

                let itemScale: CGFloat = 0.6 + CGFloat(lokiRng.next()) * 0.4
                let itemSize: CGFloat = floor(20.0 * itemScale)
                let itemFrame = CGSize(width: itemSize, height: itemSize).centered(around: position)

                let itemLayer: SimpleLayer
                if patternLayers.count > layerIndex {
                    itemLayer = patternLayers[layerIndex]
                } else {
                    itemLayer = SimpleLayer()
                    itemLayer.contents = patternImage
                    patternContainer.addSublayer(itemLayer)
                    patternLayers.append(itemLayer)
                }

                itemLayer.frame = itemFrame
                transition.updateAlpha(layer: itemLayer, alpha: (0.6 - CGFloat(row) * 0.15) * (1.0 - scaleFraction))

                layerIndex += 1
            }
        }

        while patternLayers.count > layerIndex {
            patternLayers.last?.removeFromSuperlayer()
            patternLayers.removeLast()
        }
    }

    private func updatePatternImages() {
        for layer in patternLayers {
            layer.contents = patternImage
        }
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
}

// MARK: - Craft About Features Item

public final class CraftAboutFeatureItem: GeneralRowItem {

    public struct FeatureLayout {
        public let icon: CGImage
        public let titleLayout: TextViewLayout
        public let descriptionLayout: TextViewLayout

        public var height: CGFloat {
            return max(24, titleLayout.layoutSize.height + 4 + descriptionLayout.layoutSize.height)
        }
        public init(icon: CGImage, titleLayout: TextViewLayout, descriptionLayout: TextViewLayout) {
            self.icon = icon
            self.titleLayout = titleLayout
            self.descriptionLayout = descriptionLayout
        }
    }

    fileprivate let features: [FeatureLayout]

    public init(_ initialSize: NSSize, stableId: AnyHashable, features: [GiftCraftFeature]) {
        var featureLayouts: [FeatureLayout] = []

        for feature in features {
            let titleAttr = NSAttributedString.initialize(string: feature.title, color: theme.colors.text, font: .medium(.text))
            let titleLayout = TextViewLayout(titleAttr)
            titleLayout.measure(width: initialSize.width - 80)

            let descAttr = NSAttributedString.initialize(string: feature.description, color: theme.colors.grayText, font: .normal(.text))
            let descLayout = TextViewLayout(descAttr)
            descLayout.measure(width: initialSize.width - 80)

            featureLayouts.append(FeatureLayout(
                icon: feature.icon,
                titleLayout: titleLayout,
                descriptionLayout: descLayout
            ))
        }

        self.features = featureLayouts
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    public override func viewClass() -> AnyClass {
        return CraftAboutFeatureView.self
    }

    public override var accessibilityLabel: String? {
        return features.map { "\($0.titleLayout.attributedString.string). \($0.descriptionLayout.attributedString.string)" }.joined(separator: "\n")
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override var height: CGFloat {
        var height: CGFloat = 0
        for (i, feature) in features.enumerated() {
            height += feature.height
            if i != features.count - 1 {
                height += 16
            }
        }
        return height
    }
}

private final class CraftAboutFeatureView: GeneralContainableRowView {

    private final class FeatureView: View {
        private let iconView = ImageView()
        private let titleView = TextView()
        private let descriptionView = TextView()

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(iconView)
            addSubview(titleView)
            addSubview(descriptionView)
            iconView.isAccessibilityDecorative = true

            titleView.userInteractionEnabled = false
            titleView.isSelectable = false
            descriptionView.userInteractionEnabled = false
            descriptionView.isSelectable = false
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func update(feature: CraftAboutFeatureItem.FeatureLayout) {
            iconView.image = feature.icon
            iconView.sizeToFit()
            titleView.update(feature.titleLayout)
            descriptionView.update(feature.descriptionLayout)
        }

        public override func layout() {
            super.layout()
            iconView.setFrameOrigin(NSMakePoint(0, 0))
            titleView.setFrameOrigin(NSMakePoint(40, 0))
            descriptionView.setFrameOrigin(NSMakePoint(40, titleView.frame.maxY + 4))
        }
    }

    private let featuresView = View()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(featuresView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? CraftAboutFeatureItem else {
            return
        }

        while featuresView.subviews.count > item.features.count {
            featuresView.subviews.last?.removeFromSuperview()
        }
        while featuresView.subviews.count < item.features.count {
            featuresView.addSubview(FeatureView(frame: .zero))
        }

        var y: CGFloat = 0
        for (i, feature) in item.features.enumerated() {
            let view = featuresView.subviews[i] as! FeatureView
            view.update(feature: feature)
            view.setFrameSize(NSMakeSize(frame.width - 40, feature.height))
            view.setFrameOrigin(NSMakePoint(0, y))
            y += feature.height
            if i != item.features.count - 1 {
                y += 16
            }
        }

        featuresView.setFrameSize(NSMakeSize(frame.width - 40, y))
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        featuresView.centerX(y: 0)
    }
}

// MARK: - Crafting Area Item

public final class CraftingAreaItem: GeneralRowItem {

    fileprivate let context: (any AccountContextProtocol)
    fileprivate let selectedSlots: [ProfileGiftsContext.State.StarGift?]
    fileprivate let selectedCount: Int
    fileprivate let successChance: Int
    fileprivate let variantsCount: Int
    fileprivate let giftFile: TelegramMediaFile?
    fileprivate let initialGiftRef: StarGiftReference?
    fileprivate let backdropChances: [GiftCraftChanceIndicator]
    fileprivate let patternChances: [GiftCraftChanceIndicator]
    fileprivate let craftingState: GiftCraftingState
    fileprivate let dismiss: () -> Void
    fileprivate let craft: (@escaping()->Void, @escaping(ProfileGiftsContext.State.StarGift)->Void, @escaping([ProfileGiftsContext.State.StarGift])->Void, @escaping()->Void) -> Void
    fileprivate let removeGift: (ProfileGiftsContext.State.StarGift) -> Void
    fileprivate let showModels: () -> Void
    fileprivate let showMarketplace: (Int) -> Void
    fileprivate let showAbout: () -> Void
    fileprivate let showBackdropChanceHint: (String, Int) -> Void
    fileprivate let showPatternChanceHint: (String, Int) -> Void
    fileprivate let craftAnother: () -> Void
    fileprivate let showSuccess: (StarGift.UniqueGift) -> Void

    fileprivate let titleLayout: TextViewLayout
    fileprivate let descriptionLayout: TextViewLayout
    fileprivate let variantsLayout: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, data: GiftCraftingAreaData) {
        let context = data.context
        let selectedSlots = data.selectedSlots
        let selectedCount = data.selectedCount
        let successChance = data.successChance
        let variantsCount = data.variantsCount
        let giftFile = data.giftFile
        let initialGiftRef = data.initialGiftRef
        let backdropChances = data.backdropChances
        let patternChances = data.patternChances
        let craftingState = data.craftingState
        let dismiss = data.dismiss
        let craft = data.craft
        let removeGift = data.removeGift
        let showModels = data.showModels
        let showMarketplace = data.showMarketplace
        let showAbout = data.showAbout
        let showBackdropChanceHint = data.showBackdropChanceHint
        let showPatternChanceHint = data.showPatternChanceHint
        let craftAnother = data.craftAnother
        let showSuccess = data.showSuccess
        self.context = context
        self.selectedSlots = selectedSlots
        self.selectedCount = selectedCount
        self.successChance = successChance
        self.variantsCount = variantsCount
        self.giftFile = giftFile
        self.initialGiftRef = initialGiftRef
        self.backdropChances = backdropChances
        self.patternChances = patternChances
        self.craftingState = craftingState
        self.dismiss = dismiss
        self.craft = craft
        self.removeGift = removeGift
        self.showModels = showModels
        self.showMarketplace = showMarketplace
        self.showAbout = showAbout
        self.showBackdropChanceHint = showBackdropChanceHint
        self.showPatternChanceHint = showPatternChanceHint
        self.craftAnother = craftAnother
        self.showSuccess = showSuccess

        self.titleLayout = .init(
            .initialize(
                string: strings().starGiftCraftTitle,
                color: .white,
                font: .medium(.title)
            ),
            alignment: .center
        )

        let giftName: String
        if let firstGift = selectedSlots.compactMap({ $0 }).first,
           let unique = firstGift.gift.unique {
            giftName = "\(unique.title) #\(unique.number)"
        } else {
            giftName = "gift"
        }
        let descriptionAttr = NSMutableAttributedString()
        descriptionAttr.append(string: strings().starGiftCraftDescription(clown_space, giftName), color: NSColor.white.withAlphaComponent(0.7), font: .normal(.text))
        if let giftFile = giftFile {
            descriptionAttr.insertEmbedded(.embeddedAnimated(giftFile), for: clown)
        }
        descriptionAttr.detectBoldColorInString(with: .medium(.text))
        self.descriptionLayout = .init(descriptionAttr, alignment: .center)

        let variantsAttr = NSMutableAttributedString()
        variantsAttr.append(string: strings().starGiftCraftViewAllModels(clown_space), color: .white, font: .medium(.short))
        if let giftFile = giftFile {
            variantsAttr.insertEmbedded(.embeddedAnimated(giftFile), for: clown)
        }
        self.variantsLayout = .init(variantsAttr, alignment: .center)

        super.init(initialSize, stableId: stableId)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 40)
        descriptionLayout.measure(width: width - 40)
        variantsLayout.measure(width: width - 40)
        return true
    }

    public override func viewClass() -> AnyClass {
        return CraftingAreaView.self
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return descriptionLayout.attributedString.string.replacingOccurrences(of: clown, with: "")
    }

    public override var height: CGFloat {
        let titleHeight: CGFloat = 30
        let slotsHeight: CGFloat = 150
        let textHeight = descriptionLayout.layoutSize.height
        let totalIndicators = backdropChances.count + patternChances.count
        let hasTwoRows = totalIndicators > 5
        let chanceIndicatorsHeight: CGFloat = hasTwoRows ? 90 : 40
        let variantsBadgeHeight: CGFloat = 26
        let buttonHeight: CGFloat = 40
        return titleHeight + 10 + slotsHeight + 20 + textHeight + 15 + chanceIndicatorsHeight + 10 + variantsBadgeHeight + 25 + buttonHeight + 30
    }
}

private final class CraftLostGiftView: View {
    private let modelView: NSView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 36, 36))
    private let backgroundView = UniqueGiftBackgroundView(frame: .zero)
    private var backgroundContent: UniqueGiftBackgroundContent?
    private var backgroundContext: (any AccountContextProtocol)?
    private var badgeView: ImageView?
    private let lostOverlay = View()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        addSubview(backgroundView)
        addSubview(modelView)
        (modelView as? View)?.userInteractionEnabled = false

        lostOverlay.backgroundColor = NSColor(0x8B0000).withAlphaComponent(0.4)
        lostOverlay.layer?.cornerRadius = 10
        addSubview(lostOverlay)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(gift: ProfileGiftsContext.State.StarGift, context: (any AccountContextProtocol)) {
        guard let unique = gift.gift.unique else { return }

        (modelView as? StarsStickerView)?.updateStarsSticker(file: unique.file!, size: modelView.frame.size, context: context, colors: [], playback: .loopHidden, animated: false)

        backgroundContent = UniqueGiftBackgroundContent(gift: unique)
        backgroundContext = context
        backgroundView.isHidden = backgroundContent == nil

        let badge: ImageView
        if let existing = badgeView {
            badge = existing
        } else {
            badge = ImageView()
            badge.isAccessibilityDecorative = true
            addSubview(badge)
            badgeView = badge
        }
        let colors: [NSColor] = [NSColor(0xCC3333), NSColor(0x8B0000)]
        let ribbon = generateGradientTintedImage(image: TelegramThemeHooks.shared.image(.giftRibbon).precomposed(), colors: colors, direction: .diagonal)!
        let badgeImage = generateGiftBadgeBackground(background: ribbon, text: "#\(unique.number)", textColor: .white)
        let scaledSize = NSMakeSize(badgeImage.backingSize.width * 0.5, badgeImage.backingSize.height * 0.5)
        badge.image = generateScaledImage(image: badgeImage, size: scaledSize)
        badge.setFrameSize(scaledSize)

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        lostOverlay.frame = bounds
        modelView.center()
        backgroundView.frame = bounds
        if let content = backgroundContent, let context = backgroundContext {
            backgroundView.update(context: context, content: content, style: .item(giftCenterY: modelView.frame.midY, cornerRadius: 10))
        }
        badgeView?.setFrameOrigin(NSMakePoint(frame.width - (badgeView?.frame.width ?? 0), 0))
    }
}

private final class CraftingAreaView: GeneralRowView {

    public enum CraftResult {
        case none
        case failed
        case success(gift: ProfileGiftsContext.State.StarGift)
    }

    private final class CraftChanceIndicatorView: Control {
        public enum Style {
            case backdrop([NSColor])
            case pattern(fileId: Int64, context: (any AccountContextProtocol))
        }

        private let progressTrackLayer = CAShapeLayer()
        private let progressRingLayer = CAShapeLayer()
        private let centerFill = RadialGradientView(frame: .zero)
        private var patternLayer: InlineStickerItemLayer?
        private let percentContainer = View()
        private let percentLabel = TextView()

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            progressTrackLayer.fillColor = nil
            progressTrackLayer.strokeColor = NSColor.white.withAlphaComponent(0.15).cgColor
            progressTrackLayer.lineWidth = 2
            progressTrackLayer.lineCap = .round
            layer?.addSublayer(progressTrackLayer)

            progressRingLayer.fillColor = nil
            progressRingLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
            progressRingLayer.lineWidth = 2
            progressRingLayer.lineCap = .round
            progressRingLayer.strokeEnd = 0.5
            layer?.addSublayer(progressRingLayer)

            centerFill.layer?.masksToBounds = true
            addSubview(centerFill)

            percentContainer.backgroundColor = NSColor(0x1a1a2e)
            percentContainer.layer?.masksToBounds = true
            addSubview(percentContainer)

            percentLabel.userInteractionEnabled = false
            percentLabel.isSelectable = false
            percentContainer.addSubview(percentLabel)
            self.layer?.masksToBounds = false
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func update(style: Style, percent: Int) {
            let percentLayout = TextViewLayout(
                .initialize(string: "\(percent)%", color: .white, font: .medium(8)),
                alignment: .center
            )
            percentLayout.measure(width: .greatestFiniteMagnitude)
            percentLabel.update(percentLayout)

            switch style {
            case .backdrop(let backdrop):
                centerFill.isHidden = false
                patternLayer?.removeFromSuperlayer()
                patternLayer = nil
                centerFill.colors = backdrop
            case .pattern(let fileId, let context):
                centerFill.isHidden = true
                if patternLayer?.fileId != fileId {
                    patternLayer?.removeFromSuperlayer()
                    let stickerSize = NSMakeSize(20, 20)
                    let layer = InlineStickerItemLayer(
                        account: context.account,
                        inlinePacksContext: context.inlinePacksContext,
                        emoji: .init(fileId: fileId, file: nil, emoji: clown),
                        size: stickerSize,
                        playPolicy: .loop,
                        textColor: NSColor(0xffffff)
                    )
                    layer.isPlayable = true
                    layer.noDelayBeforeplay = true
                    self.layer?.addSublayer(layer)
                    patternLayer = layer
                }
            }

            progressRingLayer.strokeEnd = CGFloat(percent) / 100.0
            needsLayout = true
        }

        public override func layout() {
            super.layout()

            let ringInset: CGFloat = 2
            let ringRadius = (min(bounds.width, bounds.height) - ringInset * 2) / 2
            let center = CGPoint(x: bounds.midX, y: bounds.midY - 4)

            let gapAngle: CGFloat = CGFloat.pi * 0.5
            let bottomAngle: CGFloat = CGFloat.pi * 0.5
            let startAngle = bottomAngle + gapAngle / 2
            let endAngle = bottomAngle - gapAngle / 2 + CGFloat.pi * 2

            let ringPath = CGMutablePath()
            ringPath.addArc(center: center, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)

            progressTrackLayer.path = ringPath
            progressTrackLayer.frame = bounds

            progressRingLayer.path = ringPath
            progressRingLayer.frame = bounds

            let fillSize: CGFloat = (ringRadius - 4) * 2
            centerFill.setFrameSize(NSMakeSize(fillSize, fillSize))
            centerFill.layer?.cornerRadius = fillSize / 2
            centerFill.setFrameOrigin(NSMakePoint(center.x - fillSize / 2, center.y - fillSize / 2))

            if let patternLayer = patternLayer {
                let layerSize = patternLayer.frame.size
                patternLayer.frame = CGRect(
                    x: center.x - layerSize.width / 2,
                    y: center.y - layerSize.height / 2,
                    width: layerSize.width,
                    height: layerSize.height
                )
            }

            let padding: CGFloat = 2
            let containerSize = NSMakeSize(percentLabel.frame.width + padding * 3, percentLabel.frame.height + padding * 2 + 1)
            percentContainer.setFrameSize(containerSize)
            percentContainer.layer?.cornerRadius = containerSize.height / 2
            percentContainer.centerX(y: bounds.height - containerSize.height)
            percentLabel.center()
        }
    }

    private let backgroundGradient = SimpleGradientLayer()
    private let centerGlow: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }()
    private let anvilPatternView = CraftAnvilPatternView(frame: NSMakeRect(0, 0, 200, 200))

    private let cubeView = CubeAnimationView(cubeSize: 90, stickerSize: 75, stickerGap: 20)
    private var cubeFaces: [SimpleLayer] = []
    private var cubeStickers: [SimpleLayer] = []
    private var isCubeAnimating = false
    private let titleView = TextView()
    private let descriptionView = InteractiveTextView()
    private let craftButton = Control()
    private let craftButtonGradient = SimpleGradientLayer()
    private let craftButtonEffect = StarsButtonEffectLayer()
    private let craftButtonTitle = TextView()
    private let craftButtonSubtitle = TextView()
    private let viewAllVariantsButton = Control()
    private let viewAllVariantsText = InteractiveTextView()
    private let viewAllVariantsChevron = ImageView()
    private let chanceIndicatorsContainer = View()
    private var chanceIndicatorViews: [CraftChanceIndicatorView] = []
    private var currentBackdropChances: [GiftCraftChanceIndicator] = []
    private var currentPatternChances: [GiftCraftChanceIndicator] = []
    private let dismissButton = ImageButton()
    private let infoButton = ImageButton()

    private var isFailedState = false
    private var isSuccessState = false
    private var failedContainer: View?

    private var pendingCraftResult: CraftResult = .none
    private var isAnimationApproachDone = false
    private var animationCompletionHandler: (() -> Void)?

    private weak var currentItem: CraftingAreaItem?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        layer?.addSublayer(backgroundGradient)
        layer?.addSublayer(centerGlow)

        addSubview(anvilPatternView)
        addSubview(cubeView)
        setupCubeFaces()

        addSubview(titleView)
        addSubview(descriptionView)

        craftButton.layer?.addSublayer(craftButtonGradient)
        craftButton.layer?.addSublayer(craftButtonEffect)
        craftButton.addSubview(craftButtonTitle)
        craftButton.addSubview(craftButtonSubtitle)
        addSubview(craftButton)

        craftButton.set(handler: { [weak self] _ in
            self?.handleCraftButtonClick()
        }, for: .Click)

        viewAllVariantsText.userInteractionEnabled = false
        viewAllVariantsButton.addSubview(viewAllVariantsText)
        let chevronIcon = generateImage(NSMakeSize(6, 10), contextGenerator: { size, ctx in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: 1, y: 1))
            ctx.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
            ctx.addLine(to: CGPoint(x: 1, y: size.height - 1))
            ctx.strokePath()
        })
        viewAllVariantsChevron.image = chevronIcon
        viewAllVariantsChevron.isAccessibilityDecorative = true
        viewAllVariantsChevron.sizeToFit()
        viewAllVariantsButton.addSubview(viewAllVariantsChevron)
        viewAllVariantsButton.scaleOnClick = true
        addSubview(viewAllVariantsButton)

        addSubview(chanceIndicatorsContainer)
        
        chanceIndicatorsContainer.layer?.masksToBounds = false

        dismissButton.scaleOnClick = true
        dismissButton.autohighlight = false
        dismissButton.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(.white), for: .Normal)
        dismissButton.setGlassEffect(size: NSMakeSize(36, 36))

        dismissButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismissButton.setAccessibilityLabel(strings().voiceOverCommonClose)
        addSubview(dismissButton)

        infoButton.scaleOnClick = true
        infoButton.autohighlight = false
        infoButton.set(image: TelegramThemeHooks.shared.image(.iconChatActionInfo).precomposed(.white), for: .Normal)
        infoButton.setGlassEffect(size: NSMakeSize(36, 36))
        infoButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        infoButton.setAccessibilityLabel(strings().voiceOverCommonInfo)
        addSubview(infoButton)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        descriptionView.userInteractionEnabled = false

        craftButtonTitle.userInteractionEnabled = false
        craftButtonTitle.isSelectable = false
        craftButtonSubtitle.userInteractionEnabled = false
        craftButtonSubtitle.isSelectable = false

        craftButton.scaleOnClick = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    private func setupCubeFaces() {
        cubeFaces.removeAll()
        for i in 0..<6 {
            if i == 0 {
                let faceLayer = CraftResultLayer(size: 90)
                cubeFaces.append(faceLayer)
            } else {
                let faceLayer = CraftSideFaceLayer(size: 90)
                cubeFaces.append(faceLayer)
            }
        }
        cubeView.setFaces(cubeFaces)
    }

    private func updateMainFaceForFailure(giftCount: Int, backgroundColor: NSColor) {
        guard !cubeFaces.isEmpty else { return }

        let newFace = CraftSideFaceLayer(size: 90)
        newFace.update(giftCount: giftCount, backgroundColor: backgroundColor)

        cubeFaces[0] = newFace
        cubeView.replaceFace(at: 0, with: newFace)
    }

    private func updateMainFaceForSuccess(gift: ProfileGiftsContext.State.StarGift, context: (any AccountContextProtocol)) {
        guard !cubeFaces.isEmpty else { return }

        let newFace = CraftGiftLayer(size: 90)
        newFace.update(gift: gift, context: context, superview: cubeView)
        newFace.setShowRemoveButton(false)
        newFace.setOnCube(true)

        cubeFaces[0] = newFace
        cubeView.replaceFace(at: 0, with: newFace)
    }

    private func resetMainFace() {
        guard !cubeFaces.isEmpty else { return }
        guard !(cubeFaces[0] is CraftResultLayer) else { return }

        let newFace = CraftResultLayer(size: 90)
        cubeFaces[0] = newFace
        cubeView.replaceFace(at: 0, with: newFace)
    }

    private func setupCubeStickers(gifts: [ProfileGiftsContext.State.StarGift?], context: (any AccountContextProtocol)) {
        for layer in cubeStickers {
            layer.removeFromSuperlayer()
        }
        cubeStickers.removeAll()

        for (index, gift) in gifts.enumerated() {
            if let gift = gift {
                let sticker = CraftGiftLayer(size: 75)
                sticker.update(gift: gift, context: context, superview: cubeView)
                sticker.setShowRemoveButton(index != 0)
                cubeStickers.append(sticker)
            } else {
                let emptySlot = EmptySlotLayer(size: 75)
                cubeStickers.append(emptySlot)
            }
        }
        cubeView.setStickers(cubeStickers)
    }

    private func startCubeAnimation(gifts: [ProfileGiftsContext.State.StarGift?], successChance: Int, context: (any AccountContextProtocol), result: CraftResult = .none, completion: @escaping () -> Void) {
        guard !isCubeAnimating else { return }
        isCubeAnimating = true
        isAnimationApproachDone = false
        pendingCraftResult = result

        for sticker in cubeStickers {
            if sticker is EmptySlotLayer {
                let duration: Double = 0.25
                sticker.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
                sticker.animateScaleCenter(from: 1.0, to: 0.1, duration: duration, removeOnCompletion: false)
            }
        }

        let giftCount = gifts.compactMap { $0 }.count
        let activeIndices = gifts.enumerated().compactMap { $0.element != nil ? $0.offset : nil }
        let resultSlotColor = successChance >= 95 ? NSColor(0x1B3C3D) : NSColor(0x253144)
        cubeView.onFinishApproach = { [weak self] isUpsideDown in
            guard let self else { return }
            self.isAnimationApproachDone = true

            self.applyResultToMainFace(giftCount: giftCount, resultSlotColor: resultSlotColor, context: context)

            for i in 0..<min(2, self.cubeStickers.count) {
                if self.cubeStickers[i] is CraftGiftLayer {
                    let face = isUpsideDown ? (i + 1) : (3 - i)
                    self.cubeView.setSticker(self.cubeStickers[i], face: face, mirror: isUpsideDown)
                }
            }
        }

        cubeView.startStickerSequence(indices: activeIndices)

        let animationDuration = Double(activeIndices.count) * 1.0 + 3.0 - 0.7
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.isCubeAnimating = false

            if case .none = self.pendingCraftResult {
                self.animationCompletionHandler = completion
            } else {
                completion()
            }
        }
    }

    private func applyResultToMainFace(giftCount: Int, resultSlotColor: NSColor, context: (any AccountContextProtocol)) {
        switch pendingCraftResult {
        case .none:
            break
        case .failed:
            updateMainFaceForFailure(giftCount: giftCount, backgroundColor: resultSlotColor)
        case .success(let gift):
            updateMainFaceForSuccess(gift: gift, context: context)
        }
    }

    public func setCraftResult(_ result: CraftResult, giftCount: Int, successChance: Int, context: (any AccountContextProtocol)) {
        pendingCraftResult = result
        let resultSlotColor = successChance >= 95 ? NSColor(0x1B3C3D) : NSColor(0x253144)

        if isAnimationApproachDone {
            applyResultToMainFace(giftCount: giftCount, resultSlotColor: resultSlotColor, context: context)
        }

        if !isCubeAnimating, let completion = animationCompletionHandler {
            animationCompletionHandler = nil
            completion()
        }
    }

    private func resetCubeAnimation(gifts: [ProfileGiftsContext.State.StarGift?], context: (any AccountContextProtocol)) {
        cubeView.resetAll()
        setupCubeStickers(gifts: gifts, context: context)
        isCubeAnimating = false
        pendingCraftResult = .none
        isAnimationApproachDone = false
        animationCompletionHandler = nil
        setCraftButtonEnabled(true)
    }

    private func setCraftButtonEnabled(_ enabled: Bool) {
        craftButton.isEnabled = enabled
        craftButtonGradient.opacity = enabled ? 1.0 : 0.5
        craftButtonTitle.layer?.opacity = enabled ? 1.0 : 0.5
        craftButtonSubtitle.layer?.opacity = enabled ? 1.0 : 0.5
    }

    private func updateChanceIndicators(item: CraftingAreaItem) {
        let allChances = currentBackdropChances + currentPatternChances
        let totalCount = allChances.count

        while chanceIndicatorViews.count > totalCount {
            chanceIndicatorViews.removeLast().removeFromSuperview()
        }
        while chanceIndicatorViews.count < totalCount {
            let view = CraftChanceIndicatorView(frame: NSMakeRect(0, 0, 40, 40))
            view.scaleOnClick = true
            chanceIndicatorsContainer.addSubview(view)
            chanceIndicatorViews.append(view)
        }

        for (index, chance) in allChances.enumerated() {
            let view = chanceIndicatorViews[index]
            let isBackdrop = index < currentBackdropChances.count

            let style: CraftChanceIndicatorView.Style
            switch chance.style {
            case .backdrop(let colors):
                style = .backdrop(colors)
            case .pattern(let fileId):
                style = .pattern(fileId: fileId, context: item.context)
            }

            view.update(style: style, percent: chance.percent)
            view.isHidden = false

            view.removeAllHandlers()
            let name = chance.name
            let percent = chance.percent
            view.set(handler: { [weak item] _ in
                if isBackdrop {
                    item?.showBackdropChanceHint(name, percent)
                } else {
                    item?.showPatternChanceHint(name, percent)
                }
            }, for: .Click)
        }

        chanceIndicatorsContainer.isHidden = allChances.isEmpty
    }

    private func handleCraftButtonClick() {
        guard let item = currentItem else { return }
        guard !isCubeAnimating else { return }

        if isFailedState {
            item.craftAnother()
        } else {
            let selectedGifts = item.selectedSlots
            let giftCount = selectedGifts.compactMap { $0 }.count
            guard giftCount > 0 else { return }

            setCraftButtonEnabled(false)

            item.craft({ [weak self, weak item] in
                guard let self, let item else { return }
                self.startCubeAnimation(gifts: selectedGifts, successChance: item.successChance, context: item.context) { [weak self, weak item] in
                    guard let self, let item else { return }
                    switch self.pendingCraftResult {
                    case .none:
                        break
                    case .success(let gift):
                        if let unique = gift.gift.unique {
                            item.showSuccess(unique)
                        }
                    case .failed:
                        let lostGifts = selectedGifts.compactMap { $0 }
                        self.showFailedState(gifts: lostGifts, context: item.context)
                    }
                }
            }, { [weak self, weak item] resultGift in
                guard let self, let item else { return }
                self.isSuccessState = true
                self.setCraftResult(.success(gift: resultGift), giftCount: giftCount, successChance: item.successChance, context: item.context)
            }, { [weak self, weak item] lostGifts in
                guard let self, let item else { return }
                self.setCraftResult(.failed, giftCount: giftCount, successChance: item.successChance, context: item.context)
            }, { [weak self] in
                self?.setCraftButtonEnabled(true)
            })
        }
    }

    private func updateCraftButton(item: CraftingAreaItem, forFailedState: Bool) {
        if forFailedState {
            craftButtonGradient.colors = [NSColor(0x3A1B15).cgColor, NSColor(0x3A1B15).cgColor]
            craftButton.layer?.borderWidth = 1
            craftButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            craftButtonSubtitle.isHidden = true
            craftButtonEffect.isHidden = true

            let buttonTitleLayout = TextViewLayout(.initialize(string: strings().starGiftCraftAnotherGift, color: .white, font: .medium(.title)), alignment: .center)
            buttonTitleLayout.measure(width: .greatestFiniteMagnitude)
            craftButtonTitle.update(buttonTitleLayout)
            craftButton.setAccessibilityLabel(strings().starGiftCraftAnotherGift)
        } else {
            if item.successChance >= 95 {
                craftButtonGradient.colors = [NSColor(0x2ECC71).cgColor, NSColor(0x27AE60).cgColor]
            } else {
                craftButtonGradient.colors = [theme.colors.accent.cgColor, theme.colors.accent.darker().cgColor]
            }
            craftButtonGradient.startPoint = CGPoint(x: 0, y: 0.5)
            craftButtonGradient.endPoint = CGPoint(x: 1, y: 0.5)
            craftButton.layer?.borderWidth = 0
            craftButton.layer?.borderColor = nil
            craftButtonSubtitle.isHidden = false
            craftButtonEffect.isHidden = false

            craftButtonEffect.color = NSColor.white.withAlphaComponent(0.6)
            craftButtonEffect.emitterLayer.emitterCells?.first?.birthRate = 10

            let craftGiftName: String
            if let firstGift = item.selectedSlots.compactMap({ $0 }).first,
               let unique = firstGift.gift.unique {
                craftGiftName = strings().starGiftCraftCraftWithName("\(unique.title) #\(unique.number)")
            } else {
                craftGiftName = strings().starGiftCraftTitle
            }
            let titleLayout = TextViewLayout(.initialize(string: craftGiftName, color: .white, font: .medium(.text)), alignment: .center)
            titleLayout.measure(width: .greatestFiniteMagnitude)
            craftButtonTitle.update(titleLayout)

            let subtitleLayout = TextViewLayout(.initialize(string: strings().starGiftCraftSuccessChance(item.successChance), color: NSColor.white.withAlphaComponent(0.8), font: .normal(.small)), alignment: .center)
            subtitleLayout.measure(width: .greatestFiniteMagnitude)
            craftButtonSubtitle.update(subtitleLayout)
            craftButton.setAccessibilityLabel("\(craftGiftName), \(strings().starGiftCraftSuccessChance(item.successChance))")
        }

        setCraftButtonEnabled(true)
    }

    private func showFailedState(gifts: [ProfileGiftsContext.State.StarGift], context: (any AccountContextProtocol)) {
        isFailedState = true

        for layer in cubeStickers {
            layer.removeFromSuperlayer()
        }
        cubeStickers.removeAll()
        cubeView.setStickers([])
        cubeView.resetAll()

        let giftCount = gifts.count
        let failedBackgroundColor = NSColor(0x3A1B15)
        for face in cubeFaces {
            if let sideFace = face as? CraftSideFaceLayer {
                sideFace.update(giftCount: giftCount, backgroundColor: failedBackgroundColor, animated: true)
            } else if let resultFace = face as? CraftResultLayer {
                resultFace.update(progress: 0, backgroundColor: failedBackgroundColor, animated: false)
            }
        }

        let animationDuration: Double = 0.25


        descriptionView.layer?.opacity = 0
        descriptionView.layer?.animateAlpha(from: 1, to: 0, duration: animationDuration, timingFunction: .easeOut)

        chanceIndicatorsContainer.layer?.opacity = 0
        chanceIndicatorsContainer.layer?.animateAlpha(from: 1, to: 0, duration: animationDuration, timingFunction: .easeOut)

        viewAllVariantsButton.layer?.opacity = 0
        viewAllVariantsButton.layer?.animateAlpha(from: 1, to: 0, duration: animationDuration, timingFunction: .easeOut)


        anvilPatternView.layer?.opacity = 0
        anvilPatternView.layer?.animateAlpha(from: 1, to: 0, duration: animationDuration, timingFunction: .easeOut)

        backgroundGradient.colors = [NSColor(0x4A241B).cgColor, NSColor(0x2A120F).cgColor]
        let buttonColor = NSColor(0x8B0000)
        centerGlow.colors = [buttonColor.withAlphaComponent(0.3).cgColor, NSColor.clear.cgColor]

        let container: View
        if let existing = self.failedContainer {
            container = existing
            container.subviews.forEach { $0.removeFromSuperview() }
        } else {
            container = View()
            container.isEventLess = true
            self.failedContainer = container
            addSubview(container)
        }

        let failedTitleView = TextView()
        failedTitleView.userInteractionEnabled = false
        failedTitleView.isSelectable = false
        container.addSubview(failedTitleView)
        let failedTitleLayout = TextViewLayout(.initialize(string: strings().starGiftCraftFailed, color: NSColor(0xFF4444), font: .medium(20)), alignment: .center)
        failedTitleLayout.measure(width: .greatestFiniteMagnitude)
        failedTitleView.update(failedTitleLayout)

        let failedDescriptionView = TextView()
        failedDescriptionView.userInteractionEnabled = false
        failedDescriptionView.isSelectable = false
        container.addSubview(failedDescriptionView)

        let descColor = NSColor(0xE8C1B2)
        let lostText = giftCount == 1 ? strings().starGiftCraftGiftLost : strings().starGiftCraftGiftsLostOther(giftCount)
        let descAttr = NSMutableAttributedString()
        descAttr.append(.initialize(string: strings().starGiftCraftFailedDescription + "\n", color: descColor, font: .normal(.text)))
        descAttr.append(.initialize(string: lostText, color: descColor, font: .bold(.text)))
        let failedDescLayout = TextViewLayout(descAttr, alignment: .center)
        failedDescLayout.measure(width: frame.width - 40)
        failedDescriptionView.update(failedDescLayout)

        let failedGiftsContainer = View()
        container.addSubview(failedGiftsContainer)

        for gift in gifts {
            let giftView = CraftLostGiftView(frame: NSMakeRect(0, 0, 60, 60))
            giftView.update(gift: gift, context: context)
            failedGiftsContainer.addSubview(giftView)
        }

        // Update craft button for failed state
        if let item = currentItem {
            updateCraftButton(item: item, forFailedState: true)
        }

        needsLayout = true

        container.layer?.animateAlpha(from: 0, to: 1, duration: animationDuration, timingFunction: .easeOut)

        failedTitleView.layer?.animatePosition(from: NSMakePoint(0, 20), to: .zero, duration: animationDuration, timingFunction: .easeOut, additive: true)
        failedDescriptionView.layer?.animatePosition(from: NSMakePoint(0, 20), to: .zero, duration: animationDuration, timingFunction: .easeOut, additive: true)
        failedGiftsContainer.layer?.animatePosition(from: NSMakePoint(0, 20), to: .zero, duration: animationDuration, timingFunction: .easeOut, additive: true)

        for giftView in failedGiftsContainer.subviews {
            giftView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeOut)
            giftView.layer?.animateScaleSpring(from: 0.35, to: 1.0, duration: 0.35, bounce: false)
        }
    }

    private func hideFailedState() {
        isFailedState = false

        let animated = true

        if let container = self.failedContainer {
            performSubviewRemoval(container, animated: animated)
            self.failedContainer = nil
        }

        backgroundGradient.colors = [NSColor(0x253144).cgColor, NSColor(0x232E3F).cgColor]
        let buttonColor = NSColor(0x6C5CE7)
        centerGlow.colors = [buttonColor.withAlphaComponent(0.2).cgColor, NSColor.clear.cgColor]

        if let item = currentItem {
            updateCraftButton(item: item, forFailedState: false)
        }

        let animationDuration: Double = 0.25

        titleView.isHidden = false
        titleView.layer?.opacity = 1
        titleView.layer?.animateAlpha(from: 0, to: 1, duration: animationDuration, timingFunction: .easeOut)

        descriptionView.isHidden = false
        descriptionView.layer?.opacity = 1
        descriptionView.layer?.animateAlpha(from: 0, to: 1, duration: animationDuration, timingFunction: .easeOut)

        chanceIndicatorsContainer.isHidden = false
        chanceIndicatorsContainer.layer?.opacity = 1
        chanceIndicatorsContainer.layer?.animateAlpha(from: 0, to: 1, duration: animationDuration, timingFunction: .easeOut)

        viewAllVariantsButton.isHidden = false
        viewAllVariantsButton.layer?.opacity = 1
        viewAllVariantsButton.layer?.animateAlpha(from: 0, to: 1, duration: animationDuration, timingFunction: .easeOut)

        craftButton.isHidden = false
        craftButton.layer?.opacity = 1
        craftButton.layer?.animateAlpha(from: 0, to: 1, duration: animationDuration, timingFunction: .easeOut)

        anvilPatternView.isHidden = false
        anvilPatternView.layer?.opacity = 1
        anvilPatternView.layer?.animateAlpha(from: 0, to: 1, duration: animationDuration, timingFunction: .easeOut)
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? CraftingAreaItem else {
            return
        }

        self.currentItem = item

        let previousFailedState = isFailedState
        let previousSuccessState = isSuccessState

        switch item.craftingState {
        case .idle:
            if previousFailedState {
                hideFailedState()
                resetMainFace()
                resetCubeAnimation(gifts: item.selectedSlots, context: item.context)
            }
            if previousSuccessState {
                resetMainFace()
                resetCubeAnimation(gifts: item.selectedSlots, context: item.context)
            }
            isFailedState = false
            isSuccessState = false
        case .crafting:
            isFailedState = false
            isSuccessState = false
        case .failed(let lostGifts):
            if !previousFailedState {
                showFailedState(gifts: lostGifts, context: item.context)
            }
            isFailedState = true
            isSuccessState = false
        }

        if case .failed = item.craftingState {
            return
        }

        if item.successChance >= 95 {
            backgroundGradient.colors = [NSColor(0x1B3C3D).cgColor, NSColor(0x232E3F).cgColor]
        } else {
            backgroundGradient.colors = [NSColor(0x253144).cgColor, NSColor(0x232E3F).cgColor]
        }
        backgroundGradient.startPoint = CGPoint(x: 0.5, y: 0)
        backgroundGradient.endPoint = CGPoint(x: 0.5, y: 1)
        backgroundGradient.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)

        let buttonColor = NSColor(0x6C5CE7)
        centerGlow.colors = [buttonColor.withAlphaComponent(0.2).cgColor, NSColor.clear.cgColor]
        centerGlow.locations = [0.0, 1.0] as [NSNumber]

        let resultSlotColor = item.successChance >= 95 ? NSColor(0x1B3C3D) : NSColor(0x253144)
        let giftCount = item.selectedSlots.compactMap { $0 }.count
        for (_, face) in cubeFaces.enumerated() {
            if let resultLayer = face as? CraftResultLayer {
                resultLayer.update(progress: item.successChance, backgroundColor: resultSlotColor, animated: animated)
            } else if let sideFace = face as? CraftSideFaceLayer {
                sideFace.update(giftCount: giftCount, backgroundColor: resultSlotColor)
            }
        }

        anvilPatternView.set(color: .white.withAlphaComponent(0.3), animated: animated)

        if !isCubeAnimating && !isFailedState {
            setupCubeStickers(gifts: item.selectedSlots, context: item.context)
        }

        cubeView.onStickerTapped = { [weak item] index in
            guard let item else { return }
            if index != 0 {
                if item.selectedSlots[index] != nil {
                    item.removeGift(item.selectedSlots[index]!)
                } else {
                    item.showMarketplace(index)
                }
            }
        }

        dismissButton.removeAllHandlers()
        dismissButton.set(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)

        infoButton.removeAllHandlers()
        infoButton.set(handler: { [weak item] _ in
            item?.showAbout()
        }, for: .Click)

        titleView.update(item.titleLayout)
        descriptionView.set(text: item.descriptionLayout, context: item.context)

        currentBackdropChances = item.backdropChances
        currentPatternChances = item.patternChances
        updateChanceIndicators(item: item)

        viewAllVariantsText.set(text: item.variantsLayout, context: item.context)
        viewAllVariantsButton.setAccessibilityLabel(strings().starGiftCraftViewAllModels("").trimmingCharacters(in: .whitespaces))
        let chevronWidth = viewAllVariantsChevron.frame.width
        let chevronSpacing: CGFloat = 4
        viewAllVariantsButton.setFrameSize(NSMakeSize(item.variantsLayout.layoutSize.width + chevronWidth + chevronSpacing + 20, item.variantsLayout.layoutSize.height + 8))
        viewAllVariantsButton.layer?.cornerRadius = viewAllVariantsButton.frame.height / 2
        viewAllVariantsText.centerY(x: 8, addition: -1)
        viewAllVariantsChevron.centerY(x: viewAllVariantsText.frame.maxX + chevronSpacing + 2)
        let variantsButtonColor = item.successChance >= 95 ? NSColor(0x1B3C3D) : NSColor(0x253144)
        viewAllVariantsButton.layer?.borderWidth = 1
        viewAllVariantsButton.layer?.borderColor = variantsButtonColor.lighter(amount: 0.3).cgColor
        viewAllVariantsButton.backgroundColor = variantsButtonColor.lighter(amount: 0.2)

        viewAllVariantsButton.removeAllHandlers()
        viewAllVariantsButton.set(handler: { [weak item] _ in
            item?.showModels()
        }, for: .Click)

        updateCraftButton(item: item, forFailedState: false)

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        backgroundGradient.frame = bounds

        let slotSize: CGFloat = 70
        let slotInsetX: CGFloat = 20
        let slotInsetY: CGFloat = 50
        let slotGap: CGFloat = 14

        let slotsAreaHeight = slotSize * 2 + slotGap
        let cubeViewSize = NSMakeSize(frame.width - slotInsetX * 2, slotsAreaHeight)
        cubeView.setFrameSize(cubeViewSize)
        cubeView.setFrameOrigin(NSMakePoint(slotInsetX, slotInsetY))

        let stickerPositions: [CGPoint] = [
            CGPoint(x: slotInsetX / 2, y: 0),
            CGPoint(x: cubeViewSize.width - slotSize, y: 0),
            CGPoint(x: slotInsetX / 2, y: slotSize + slotGap),
            CGPoint(x: cubeViewSize.width - slotSize, y: slotSize + slotGap)
        ]
        cubeView.setStickerPositions(stickerPositions)

        let anvilPatternSize = NSMakeSize(200, 200)
        anvilPatternView.setFrameSize(anvilPatternSize)
        let cubeCenter = NSMakePoint(cubeView.frame.midX, cubeView.frame.midY)
        anvilPatternView.setFrameOrigin(NSMakePoint(cubeCenter.x - anvilPatternSize.width / 2, cubeCenter.y - anvilPatternSize.height / 2))

        let glowSize: CGFloat = 400
        centerGlow.frame = NSMakeRect((frame.width - glowSize) / 2, slotInsetY + (slotSize * 2 + slotGap - glowSize) / 2, glowSize, glowSize)

        titleView.centerX(y: 15)
        dismissButton.setFrameOrigin(NSMakePoint(10, 10))
        infoButton.setFrameOrigin(NSMakePoint(frame.width - infoButton.frame.width - 10, 10))

        let slotsEndY = slotInsetY + slotSize * 2 + slotGap
        descriptionView.centerX(y: slotsEndY + 20)

        let indicatorSize: CGFloat = 40
        let indicatorGap: CGFloat = 20
        let rowGap: CGFloat = 10
        let indicatorsY = descriptionView.frame.maxY + 15

        let backdropCount = currentBackdropChances.count
        let patternCount = currentPatternChances.count
        let totalCount = backdropCount + patternCount

        var containerHeight: CGFloat = 0
        var containerWidth: CGFloat = 0

        if totalCount > 0 {
            let hasTwoRows = totalCount > 5

            if hasTwoRows {
                let row2Count = (totalCount + 1) / 2
                let row1Count = totalCount - row2Count

                let row1Width = CGFloat(row1Count) * indicatorSize + CGFloat(max(0, row1Count - 1)) * indicatorGap
                let row2Width = CGFloat(row2Count) * indicatorSize + CGFloat(max(0, row2Count - 1)) * indicatorGap
                containerWidth = max(row1Width, row2Width)
                containerHeight = indicatorSize * 2 + rowGap

                var x: CGFloat = (containerWidth - row1Width) / 2
                for i in 0..<row1Count {
                    let view = chanceIndicatorViews[i]
                    view.setFrameSize(NSMakeSize(indicatorSize, indicatorSize))
                    view.setFrameOrigin(NSMakePoint(x, 0))
                    x += indicatorSize + indicatorGap
                }

                x = (containerWidth - row2Width) / 2
                for i in 0..<row2Count {
                    let view = chanceIndicatorViews[row1Count + i]
                    view.setFrameSize(NSMakeSize(indicatorSize, indicatorSize))
                    view.setFrameOrigin(NSMakePoint(x, indicatorSize + rowGap))
                    x += indicatorSize + indicatorGap
                }
            } else {
                containerWidth = CGFloat(totalCount) * indicatorSize + CGFloat(max(0, totalCount - 1)) * indicatorGap
                containerHeight = indicatorSize

                var x: CGFloat = 0
                for view in chanceIndicatorViews {
                    view.setFrameSize(NSMakeSize(indicatorSize, indicatorSize))
                    view.setFrameOrigin(NSMakePoint(x, 0))
                    x += indicatorSize + indicatorGap
                }
            }
        }

        chanceIndicatorsContainer.setFrameSize(NSMakeSize(containerWidth, containerHeight))
        chanceIndicatorsContainer.centerX(y: indicatorsY)

        viewAllVariantsButton.centerX(y: chanceIndicatorsContainer.frame.maxY + 10)

        let buttonHeight: CGFloat = 40
        craftButton.setFrameSize(NSMakeSize(frame.width - 40, buttonHeight))
        craftButton.centerX(y: viewAllVariantsButton.frame.maxY + 25)
        craftButton.layer?.cornerRadius = buttonHeight / 2
        craftButtonGradient.frame = craftButton.bounds
        craftButtonGradient.cornerRadius = buttonHeight / 2

        let buttonEffectSize = NSMakeSize(craftButton.frame.width + 30, craftButton.frame.height + 30)
        craftButtonEffect.frame = NSMakeRect(-15, -15, buttonEffectSize.width, buttonEffectSize.height)
        craftButtonEffect.update(size: buttonEffectSize)

        if craftButtonSubtitle.isHidden {
            craftButtonTitle.centerX(y: (buttonHeight - craftButtonTitle.frame.height) / 2)
        } else {
            let titleHeight = craftButtonTitle.frame.height
            let subtitleHeight = craftButtonSubtitle.frame.height
            let contentHeight = titleHeight + 2 + subtitleHeight
            let startY = (buttonHeight - contentHeight) / 2
            craftButtonTitle.centerX(y: startY + 1)
            craftButtonSubtitle.centerX(y: craftButtonTitle.frame.maxY + 2)
        }

        if isFailedState, let container = self.failedContainer {
            let slotsEndY = slotInsetY + slotSize * 2 + slotGap
            container.frame = NSMakeRect(0, slotsEndY, frame.width, frame.height - slotsEndY)

            var failedY: CGFloat = 15
            if let titleView = container.subviews.first(where: { $0 is TextView }) as? TextView {
                titleView.centerX(y: failedY)
                failedY = titleView.frame.maxY + 8
            }

            if container.subviews.count > 1, let descView = container.subviews[1] as? TextView {
                descView.centerX(y: failedY)
                failedY = descView.frame.maxY + 35
            }

            if let giftsContainer = container.subviews.first(where: { !($0 is TextView) }) {
                let giftViews = giftsContainer.subviews
                let giftViewWidth: CGFloat = 60
                let giftViewHeight: CGFloat = 60
                let giftGap: CGFloat = 12
                let totalGiftsWidth = CGFloat(giftViews.count) * giftViewWidth + CGFloat(max(0, giftViews.count - 1)) * giftGap
                var giftX: CGFloat = 0

                giftsContainer.setFrameSize(NSMakeSize(totalGiftsWidth, giftViewHeight))
                giftsContainer.centerX(y: failedY)

                for giftView in giftViews {
                    giftView.setFrameSize(NSMakeSize(giftViewWidth, giftViewHeight))
                    giftView.setFrameOrigin(NSMakePoint(giftX, 0))
                    giftX += giftViewWidth + giftGap
                }
            }

        }
    }
}
