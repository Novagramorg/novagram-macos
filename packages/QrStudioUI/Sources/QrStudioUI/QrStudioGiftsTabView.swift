import Foundation
import Cocoa
import CoreText
import TGUIKit
import TelegramCore
import TelegramContext
import TelegramMedia
import ColorPalette
import UniqueGiftBackground
import InlineStickerLayer
import Localization

private var qrStudioNoGiftsAnimationData: Data?

private func qrStudioNoGiftsAnimation() -> Data? {
    if let data = qrStudioNoGiftsAnimationData {
        return data
    }
    guard let url = Bundle.module.url(forResource: "QrStudioNoGifts", withExtension: "tgs"), let data = try? Data(contentsOf: url) else {
        return nil
    }
    qrStudioNoGiftsAnimationData = data
    return data
}

private final class QrStudioGiftTileView: View {
    private let backgroundView = UniqueGiftBackgroundView(frame: .zero)
    private let trimMask = SimpleShapeLayer()
    private let stickerView = View()
    private let ringView = View()
    private let ring = SimpleShapeLayer()
    private var sticker: InlineStickerItemLayer?
    private var stickerKey: (Int64, CGFloat)?
    private var isSelected: Bool?

    static let cornerRadius: CGFloat = 16.0
    static let lineWidth: CGFloat = 2.0

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isEventLess = true
        self.layer?.masksToBounds = false

        self.trimMask.fillColor = NSColor.black.cgColor
        self.backgroundView.layer?.mask = self.trimMask
        self.addSubview(self.backgroundView)

        self.stickerView.isEventLess = true
        self.stickerView.layer?.masksToBounds = false
        self.addSubview(self.stickerView)

        self.ring.fillColor = nil
        self.ring.lineWidth = 0.0
        self.ringView.isEventLess = true
        self.ringView.layer?.masksToBounds = false
        self.ringView.layer?.addSublayer(self.ring)
        self.addSubview(self.ringView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func roundedPath(size: CGSize, inset: CGFloat, cornerRadius: CGFloat) -> CGPath {
        let rect = CGRect(origin: CGPoint(), size: size).insetBy(dx: inset, dy: inset)
        let radius = min(max(0.0, cornerRadius), min(rect.width, rect.height) * 0.5)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func update(context: any AccountContextProtocol, gift: QrStudioGift, size: CGSize, isSelected: Bool, animated: Bool) {
        let bounds = CGRect(origin: CGPoint(), size: size)
        let backgroundFrame = bounds.insetBy(dx: 2.0, dy: 2.0)
        let iconSide = floor(size.width * 0.7)
        let iconFrame = CGRect(x: floor((size.width - iconSide) * 0.5), y: floor((size.height - iconSide) * 0.5), width: iconSide, height: iconSide)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.backgroundView.frame = backgroundFrame
        self.backgroundView.update(context: context, content: UniqueGiftBackgroundContent(gift: gift.gift), style: .item(giftCenterY: iconFrame.midY - backgroundFrame.minY, cornerRadius: QrStudioGiftTileView.cornerRadius))

        self.stickerView.frame = bounds
        if self.stickerKey?.0 != gift.model.fileId.id || self.stickerKey?.1 != iconSide {
            self.sticker?.removeFromSuperlayer()
            let sticker = InlineStickerItemLayer(account: context.account, file: gift.model, size: iconFrame.size, playPolicy: .onceEnd)
            sticker.superview = self.stickerView
            self.stickerView.layer?.addSublayer(sticker)
            sticker.isPlayable = true
            self.sticker = sticker
            self.stickerKey = (gift.model.fileId.id, iconSide)
        }
        self.sticker?.frame = iconFrame

        self.ringView.frame = bounds

        let wasSelected = self.isSelected ?? false
        self.isSelected = isSelected
        let animates = animated && wasSelected != isSelected

        let lineWidth = QrStudioGiftTileView.lineWidth
        let trimInset: CGFloat = isSelected ? lineWidth * 2.0 : 0.0
        let trimPath = QrStudioGiftTileView.roundedPath(size: backgroundFrame.size, inset: trimInset, cornerRadius: QrStudioGiftTileView.cornerRadius - trimInset)
        let previousTrimPath = self.trimMask.presentation()?.path ?? self.trimMask.path
        self.trimMask.frame = CGRect(origin: CGPoint(), size: backgroundFrame.size)
        self.trimMask.path = trimPath

        let ringRadius = QrStudioGiftTileView.cornerRadius - lineWidth * 0.5
        let ringLineWidth: CGFloat = isSelected ? lineWidth : 0.0
        let ringPath = QrStudioGiftTileView.roundedPath(size: backgroundFrame.size, inset: isSelected ? lineWidth * 0.5 : 0.0, cornerRadius: ringRadius)
        let previousRingPath = self.ring.presentation()?.path ?? self.ring.path
        let previousRingLineWidth = self.ring.presentation()?.lineWidth ?? self.ring.lineWidth
        self.ring.frame = backgroundFrame
        self.ring.strokeColor = gift.outer.nsColor.cgColor
        self.ring.path = ringPath
        self.ring.lineWidth = ringLineWidth

        CATransaction.commit()

        guard animates else {
            return
        }
        if let previousTrimPath {
            self.trimMask.animate(from: previousTrimPath, to: trimPath, keyPath: "path", timingFunction: .easeInEaseOut, duration: 0.2)
        }
        if let previousRingPath {
            self.ring.animate(from: previousRingPath, to: ringPath, keyPath: "path", timingFunction: .easeInEaseOut, duration: 0.2)
        }
        self.ring.animate(from: NSNumber(value: Double(previousRingLineWidth)), to: NSNumber(value: Double(ringLineWidth)), keyPath: "lineWidth", timingFunction: .easeInEaseOut, duration: 0.2)
    }
}

private final class QrStudioGiftsDocumentView: View {
    var click: ((NSPoint) -> Void)?
    private var downPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        self.downPoint = self.convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        if let downPoint = self.downPoint, abs(downPoint.x - point.x) < 8.0, abs(downPoint.y - point.y) < 8.0 {
            self.click?(point)
        }
        self.downPoint = nil
    }
}

private final class QrStudioBrowseButton: TextButton {
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let textView = self.subviews.compactMap({ $0 as? TextView }).first,
              let layout = textView.textLayout, let line = layout.lines.first else {
            return
        }
        let glyphBounds = CTLineGetBoundsWithOptions(line.line, .useGlyphPathBounds)
        guard !glyphBounds.isEmpty else {
            return
        }
        let baseline = (textView.frame.height - layout.layoutSize.height) * 0.5 + line.frame.minY
        var frame = textView.frame
        frame.origin.y = floorToScreenPixels(self.backingScaleFactor, size.height * 0.5 - baseline + glyphBounds.midY)
        transition.updateFrame(view: textView, frame: frame)
    }
}

final class QrStudioGiftsTabView: View {
    private struct Params {
        let size: CGSize
        let context: any AccountContextProtocol
        let gifts: [QrStudioGift]
        let selectedId: Int64?
        let isDark: Bool
    }

    let scrollView = ScrollView()
    var selected: ((Int64) -> Void)?
    var loadMore: (() -> Void)?
    var browse: (() -> Void)?

    private let documentView = QrStudioGiftsDocumentView()
    private let emptyView = View()
    private let emptyPlayer = LottiePlayerView(frame: .zero)
    private let emptyTitleView = TextView()
    private let emptyTextView = TextView()
    private let browseButton = QrStudioBrowseButton()
    private var appliedEmptyKey: (CGSize, Bool)?
    private let titleView = TextView()
    private var items: [Int64: QrStudioGiftTileView] = [:]
    private var params: Params?
    private var appliedTitleKey: (CGFloat, Bool)?
    private var contentHeight: CGFloat = 0.0
    private var scrollObserver: NSObjectProtocol?

    private static let sideInset: CGFloat = 16.0
    private static let spacing: CGFloat = 10.0
    private static let columns = 3
    private static let top: CGFloat = 16.0 + 17.0 + 12.0
    private static let title = strings().qrStudioGiftsTabViewTitle
    private static let emptyTitle = strings().qrStudioGiftsTabViewEmptyTitle
    private static let emptyText = strings().qrStudioGiftsTabViewEmptyText
    private static let browseTitle = strings().qrStudioGiftsTabViewBrowse

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.scrollView.background = .clear
        self.scrollView.hasVerticalScroller = false
        self.scrollView.verticalScrollElasticity = .allowed
        self.scrollView.documentView = self.documentView
        self.addSubview(self.scrollView)

        self.titleView.userInteractionEnabled = false
        self.titleView.isSelectable = false
        self.titleView.isEventLess = true
        self.documentView.addSubview(self.titleView)

        self.documentView.click = { [weak self] point in
            self?.handleClick(point)
        }

        self.emptyView.isHidden = true
        self.emptyPlayer.isEventLess = true
        self.emptyView.addSubview(self.emptyPlayer)
        for textView in [self.emptyTitleView, self.emptyTextView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            textView.isEventLess = true
            self.emptyView.addSubview(textView)
        }
        self.browseButton.autohighlight = false
        self.browseButton.scaleOnClick = true
        self.browseButton.layer?.cornerRadius = 20.0
        self.browseButton.set(font: .semibold(15.0), for: .Normal)
        self.browseButton.set(color: NSColor.white, for: .Normal)
        self.browseButton.set(text: QrStudioGiftsTabView.browseTitle, for: .Normal)
        self.browseButton.set(handler: { [weak self] _ in
            self?.browse?()
        }, for: .Click)
        self.emptyView.addSubview(self.browseButton)
        self.documentView.addSubview(self.emptyView)

        self.scrollView.contentView.postsBoundsChangedNotifications = true
        self.scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: self.scrollView.contentView, queue: nil, using: { [weak self] _ in
            self?.scrollViewDidScroll()
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollObserver = self.scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    private func scrollViewDidScroll() {
        self.updateVisibleItems(animated: false)
        let visible = self.scrollView.documentVisibleRect
        if self.params?.gifts.isEmpty == false, visible.maxY > self.contentHeight - 200.0 {
            self.loadMore?()
        }
    }

    private func handleClick(_ point: NSPoint) {
        guard let params = self.params, params.size.width > 0.0 else {
            return
        }
        let itemSide = self.itemSide(width: params.size.width)
        for (index, gift) in params.gifts.enumerated() where self.itemFrame(index: index, itemSide: itemSide).contains(point) {
            self.selected?(gift.id)
            return
        }
    }

    private func itemSide(width: CGFloat) -> CGFloat {
        let columns = CGFloat(QrStudioGiftsTabView.columns)
        return floor((width - QrStudioGiftsTabView.sideInset * 2.0 - QrStudioGiftsTabView.spacing * (columns - 1.0)) / columns)
    }

    private func itemFrame(index: Int, itemSide: CGFloat) -> CGRect {
        let column = index % QrStudioGiftsTabView.columns
        let row = index / QrStudioGiftsTabView.columns
        return CGRect(x: QrStudioGiftsTabView.sideInset + CGFloat(column) * (itemSide + QrStudioGiftsTabView.spacing), y: QrStudioGiftsTabView.top + CGFloat(row) * (itemSide + QrStudioGiftsTabView.spacing), width: itemSide, height: itemSide)
    }

    func update(size: CGSize, context: any AccountContextProtocol, gifts: [QrStudioGift], isLoaded: Bool, selectedId: Int64?, revealSelection: Bool, scrollsToSelection: Bool, isDark: Bool) {
        if self.params?.gifts.isEmpty != gifts.isEmpty {
            self.appliedEmptyKey = nil
            self.scrollView.contentView.scroll(to: .zero)
        }
        self.params = Params(size: size, context: context, gifts: gifts, selectedId: selectedId, isDark: isDark)
        self.scrollView.frame = CGRect(origin: CGPoint(), size: size)

        let isEmpty = gifts.isEmpty
        self.scrollView.isHidden = isEmpty && !isLoaded
        self.titleView.isHidden = isEmpty
        self.emptyView.isHidden = !(isEmpty && isLoaded)
        self.updateEmptyPlayback()
        if isEmpty {
            if isLoaded {
                self.updateEmptyState(size: size, isDark: isDark)
            }
            self.updateVisibleItems(animated: false)
            return
        }

        if self.appliedTitleKey?.0 != size.width || self.appliedTitleKey?.1 != isDark {
            self.appliedTitleKey = (size.width, isDark)
            let palette = qrStudioSheetPalette(isDark: isDark)
            let title = NSAttributedString(string: QrStudioGiftsTabView.title.uppercased(), attributes: [
                .font: NSFont.semibold(13.0),
                .foregroundColor: palette.grayText,
                .kern: -0.078
            ])
            let layout = TextViewLayout(title, maximumNumberOfLines: 1, alignment: .center)
            layout.measure(width: max(1.0, size.width - 4.0))
            self.titleView.update(layout)
            self.titleView.frame = CGRect(x: floor((size.width - layout.layoutSize.width) * 0.5), y: 16.0 + floor((17.0 - layout.layoutSize.height) * 0.5), width: layout.layoutSize.width, height: layout.layoutSize.height)
        }

        let itemSide = self.itemSide(width: size.width)
        let rows = (gifts.count + QrStudioGiftsTabView.columns - 1) / QrStudioGiftsTabView.columns
        self.contentHeight = QrStudioGiftsTabView.top + CGFloat(rows) * itemSide + CGFloat(max(0, rows - 1)) * QrStudioGiftsTabView.spacing + 12.0 + 40.0
        let documentFrame = CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: max(self.contentHeight, size.height)))
        if self.documentView.frame != documentFrame {
            self.documentView.frame = documentFrame
        }

        if revealSelection, scrollsToSelection, size.height > 0.0, let selectedId, let index = gifts.firstIndex(where: { $0.id == selectedId }) {
            let frame = self.itemFrame(index: index, itemSide: itemSide)
            let offset = self.scrollView.documentVisibleRect.minY
            if frame.minY < offset + 14.0 || frame.maxY > offset + size.height - 40.0 {
                let maxOffset = max(0.0, self.contentHeight - size.height)
                self.scrollView.contentView.scroll(to: NSPoint(x: 0.0, y: min(maxOffset, max(0.0, frame.midY - size.height * 0.5))))
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            }
        }

        self.updateVisibleItems(animated: !revealSelection)
    }

    private static let emptyStickerSide: CGFloat = 100.0

    private func updateEmptyPlayback() {
        let visible = self.window != nil && !self.emptyView.isHidden && !self.emptyPlayer.frame.isEmpty
        if visible {
            if self.emptyPlayer.animation == nil, let data = qrStudioNoGiftsAnimation() {
                let side = QrStudioGiftsTabView.emptyStickerSide
                self.emptyPlayer.set(LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .bundle("qr_studio_no_gifts"), size: NSMakeSize(side, side)), cachePurpose: .none, playPolicy: .loop, maximumFps: 60))
            }
        } else if self.emptyPlayer.animation != nil {
            self.emptyPlayer.set(nil)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateEmptyPlayback()
    }

    private func updateEmptyState(size: CGSize, isDark: Bool) {
        let sizeChanged = self.appliedEmptyKey?.0 != size
        let isDarkChanged = self.appliedEmptyKey?.1 != isDark
        guard sizeChanged || isDarkChanged else {
            return
        }
        self.appliedEmptyKey = (size, isDark)
        let palette = qrStudioSheetPalette(isDark: isDark)
        let width = max(1.0, size.width - 32.0)

        let titleLayout = TextViewLayout(NSAttributedString(string: QrStudioGiftsTabView.emptyTitle, attributes: [.font: NSFont.semibold(20.0), .foregroundColor: palette.text]), alignment: .center)
        titleLayout.measure(width: width)
        self.emptyTitleView.update(titleLayout)

        let textLayout = TextViewLayout(NSAttributedString(string: QrStudioGiftsTabView.emptyText, attributes: [.font: NSFont.normal(15.0), .foregroundColor: palette.grayText]), alignment: .center)
        textLayout.measure(width: width)
        self.emptyTextView.update(textLayout)

        let verticalInset: CGFloat = 16.0
        let textAndButtonHeight = 12.0 + titleLayout.layoutSize.height + 6.0 + textLayout.layoutSize.height + 18.0 + 40.0
        let stickerSide = min(QrStudioGiftsTabView.emptyStickerSide, max(40.0, size.height - verticalInset * 2.0 - textAndButtonHeight))
        let contentHeight = stickerSide + textAndButtonHeight
        self.contentHeight = max(size.height, contentHeight + verticalInset * 2.0)
        self.documentView.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: self.contentHeight))
        self.emptyView.frame = self.documentView.bounds
        var y = max(verticalInset, floor((size.height - contentHeight) * 0.5))
        self.emptyPlayer.frame = CGRect(x: floor((size.width - stickerSide) * 0.5), y: y, width: stickerSide, height: stickerSide)
        self.updateEmptyPlayback()
        y += stickerSide + 12.0
        self.emptyTitleView.frame = CGRect(x: floor((size.width - titleLayout.layoutSize.width) * 0.5), y: y, width: titleLayout.layoutSize.width, height: titleLayout.layoutSize.height)
        y += titleLayout.layoutSize.height + 6.0
        self.emptyTextView.frame = CGRect(x: floor((size.width - textLayout.layoutSize.width) * 0.5), y: y, width: textLayout.layoutSize.width, height: textLayout.layoutSize.height)
        y += textLayout.layoutSize.height + 18.0

        self.browseButton.set(background: palette.accent, for: .Normal)
        _ = self.browseButton.sizeToFit(NSMakeSize(44.0, 0.0))
        let buttonWidth = self.browseButton.frame.width
        self.browseButton.frame = CGRect(x: floor((size.width - buttonWidth) * 0.5), y: y, width: buttonWidth, height: 40.0)
    }

    private func updateVisibleItems(animated: Bool) {
        guard let params = self.params, params.size.width > 0.0 else {
            return
        }
        let itemSide = self.itemSide(width: params.size.width)
        let itemSize = CGSize(width: itemSide, height: itemSide)
        let visibleRect = self.scrollView.documentVisibleRect.insetBy(dx: 0.0, dy: -itemSide)

        var validIds = Set<Int64>()
        for (index, gift) in params.gifts.enumerated() {
            let frame = self.itemFrame(index: index, itemSide: itemSide)
            guard frame.intersects(visibleRect) else {
                continue
            }
            validIds.insert(gift.id)
            let item: QrStudioGiftTileView
            var isNew = false
            if let current = self.items[gift.id] {
                item = current
            } else {
                item = QrStudioGiftTileView(frame: frame)
                self.items[gift.id] = item
                self.documentView.addSubview(item)
                isNew = true
            }
            if item.frame != frame {
                item.frame = frame
            }
            item.update(context: params.context, gift: gift, size: itemSize, isSelected: gift.id == params.selectedId, animated: animated && !isNew)
        }
        for (id, item) in self.items where !validIds.contains(id) {
            item.removeFromSuperview()
            self.items.removeValue(forKey: id)
        }
    }
}
