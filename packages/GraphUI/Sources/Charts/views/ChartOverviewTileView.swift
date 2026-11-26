import Cocoa
import TGUIKit

private let tileInsets = NSEdgeInsets(top: 11, left: 14, bottom: 12, right: 14)
private let tileCornerRadius: CGFloat = 20
private let titleSpacing: CGFloat = 3
private let pillHeight: CGFloat = 18
private let pillPadding: CGFloat = 7
private let pillSpacing: CGFloat = 8
private let titleFont = NSFont.systemFont(ofSize: 12, weight: .regular)
private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
private let detailFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

public final class ChartOverviewTileView: View {
    public struct Content: Equatable {
        public let title: String
        public let value: String
        public let detail: String
        public let titleColor: NSColor
        public let valueColor: NSColor
        public let detailColor: NSColor
        public let detailTinted: Bool

        public init(title: String, value: String, detail: String, titleColor: NSColor, valueColor: NSColor, detailColor: NSColor, detailTinted: Bool) {
            self.title = title
            self.value = value
            self.detail = detail
            self.titleColor = titleColor
            self.valueColor = valueColor
            self.detailColor = detailColor
            self.detailTinted = detailTinted
        }
    }

    public static func height(for content: Content) -> CGFloat {
        let titleLayout = TextViewLayout(.initialize(string: content.title, color: content.titleColor, font: titleFont), maximumNumberOfLines: 1, truncationType: .end)
        titleLayout.measure(width: .greatestFiniteMagnitude)
        return tileInsets.top + titleLayout.layoutSize.height + titleSpacing + self.valueRowHeight + tileInsets.bottom
    }

    private static var valueRowHeight: CGFloat {
        return max(ChartMorphingTextView.size(of: "0", font: valueFont).height, pillHeight)
    }

    private let titleView = TextView()
    private let valueView = ChartMorphingTextView(frame: .zero)
    private let pillView = View()
    private let detailView = ChartMorphingTextView(frame: .zero)
    private var titleLayout: TextViewLayout?
    private var content: Content?
    private var isDark: Bool?
    private var skeletonView: ChartSkeletonView?
    
    public var isSkeleton: Bool {
        return self.skeletonView != nil
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.cornerRadius = tileCornerRadius
        self.titleView.userInteractionEnabled = false
        self.titleView.isSelectable = false
        self.titleView.disableBackgroundDrawing = true
        self.addSubview(self.titleView)
        self.valueView.clipsToRow = true
        self.addSubview(self.valueView)
        self.pillView.isEventLess = true
        self.pillView.layer?.cornerRadius = pillHeight / 2
        self.addSubview(self.pillView)
        self.detailView.clipsToRow = true
        self.pillView.addSubview(self.detailView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showSkeleton(cardColor: NSColor, isDark: Bool) {
        self.updateCard(color: cardColor, isDark: isDark)
        let skeletonView: ChartSkeletonView
        if let current = self.skeletonView {
            skeletonView = current
        } else {
            skeletonView = ChartSkeletonView(frame: self.bounds)
            self.addSubview(skeletonView, positioned: .below, relativeTo: self.titleView)
            self.skeletonView = skeletonView
        }
        self.content = nil
        self.titleView.isHidden = true
        self.valueView.isHidden = true
        self.pillView.isHidden = true
        self.layoutSkeleton()
    }
    
    private func layoutSkeleton() {
        guard let skeletonView = self.skeletonView else {
            return
        }
        skeletonView.frame = self.bounds
        let colors = ChartSkeletonView.colors(isDark: self.isDark ?? false)
        let titleTop = tileInsets.top + 3
        let valueTop = tileInsets.top + 16 + titleSpacing + 3
        skeletonView.update(shapes: [
            .roundedRect(CGRect(x: tileInsets.left, y: titleTop, width: min(84, self.bounds.width - tileInsets.left * 2), height: 10), cornerRadius: 5),
            .roundedRect(CGRect(x: tileInsets.left, y: valueTop, width: min(118, self.bounds.width - tileInsets.left * 2), height: 18), cornerRadius: 7)
        ], baseColor: colors.base, highlightColor: colors.highlight)
    }
    
    private func updateCard(color: NSColor, isDark: Bool) {
        self.backgroundColor = color
        if self.isDark != isDark {
            self.isDark = isDark
            self.layoutSkeleton()
        }
    }
    
    private func zeroed(_ text: String) -> String {
        return String(text.map { $0.isNumber ? "0" : $0 })
    }
    
    private func revealFromSkeleton(content: Content, isDark: Bool) {
        guard let skeletonView = self.skeletonView else {
            return
        }
        self.skeletonView = nil
        skeletonView.layer?.animateAlpha(from: 1, to: 0, duration: 0.22, removeOnCompletion: false, completion: { [weak skeletonView] _ in
            skeletonView?.removeFromSuperview()
        })
        self.titleView.isHidden = false
        self.valueView.isHidden = false
        self.titleLayout = TextViewLayout(.initialize(string: content.title, color: content.titleColor, font: titleFont), maximumNumberOfLines: 1, truncationType: .end)
        self.valueView.update(text: self.zeroed(content.value), font: valueFont, color: content.valueColor, animated: false)
        self.detailView.update(text: self.zeroed(content.detail), font: detailFont, color: content.detailColor, animated: false)
        self.valueView.update(text: content.value, font: valueFont, color: content.valueColor, animated: true)
        self.detailView.update(text: content.detail, font: detailFont, color: content.detailColor, animated: true)
        self.pillView.backgroundColor = content.detailTinted ? content.detailColor.withAlphaComponent(isDark ? 0.2 : 0.13) : .clear
        self.pillView.isHidden = content.detail.isEmpty
        self.content = content
        self.layoutContent(animated: false)
        self.titleView.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
        if !self.pillView.isHidden {
            self.pillView.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
            self.pillView.layer?.animateScaleSpring(from: 0.7, to: 1, duration: 0.45, bounce: false)
        }
    }
    
    public func update(content: Content, cardColor: NSColor, isDark: Bool, animated: Bool) {
        if self.skeletonView != nil {
            self.updateCard(color: cardColor, isDark: isDark)
            if animated && self.window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.revealFromSkeleton(content: content, isDark: isDark)
                return
            }
            self.skeletonView?.removeFromSuperview()
            self.skeletonView = nil
            self.titleView.isHidden = false
            self.valueView.isHidden = false
        }
        self.updateCard(color: cardColor, isDark: isDark)
        let animated = animated && self.content != nil && self.window != nil
        if self.content?.title != content.title || self.content?.titleColor != content.titleColor {
            self.titleLayout = TextViewLayout(.initialize(string: content.title, color: content.titleColor, font: titleFont), maximumNumberOfLines: 1, truncationType: .end)
        }
        self.valueView.update(text: content.value, font: valueFont, color: content.valueColor, animated: animated)
        self.detailView.update(text: content.detail, font: detailFont, color: content.detailColor, animated: animated)
        let pillColor = content.detailTinted ? content.detailColor.withAlphaComponent(isDark ? 0.2 : 0.13) : .clear
        if animated, let layer = self.pillView.layer, let from = layer.presentation()?.backgroundColor ?? layer.backgroundColor, from != pillColor.cgColor {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = from
            animation.toValue = pillColor.cgColor
            animation.duration = 0.25
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "backgroundColor")
        }
        self.pillView.backgroundColor = pillColor
        self.pillView.isHidden = content.detail.isEmpty
        self.content = content
        self.layoutContent(animated: animated)
    }

    public override func layout() {
        super.layout()
        self.layoutSkeleton()
        self.layoutContent(animated: false)
    }

    private func layoutContent(animated: Bool) {
        guard let content = self.content else {
            return
        }
        let width = self.bounds.width - tileInsets.left - tileInsets.right
        var y = tileInsets.top
        if let layout = self.titleLayout {
            layout.measure(width: width)
            self.titleView.update(layout)
            self.titleView.setFrameOrigin(NSPoint(x: tileInsets.left, y: y))
            y += layout.layoutSize.height + titleSpacing
        }
        let rowHeight = ChartOverviewTileView.valueRowHeight
        self.valueView.frame = CGRect(x: tileInsets.left, y: y, width: width, height: rowHeight)
        let padding = content.detailTinted ? pillPadding : 0
        let pillWidth = self.detailView.contentSize.width + padding * 2
        let valueWidth = self.valueView.contentSize.width
        let pillFrame = CGRect(x: min(tileInsets.left + valueWidth + pillSpacing, self.bounds.width - tileInsets.right - pillWidth), y: y + floor((rowHeight - pillHeight) / 2) + 1, width: pillWidth, height: pillHeight)
        if animated && !self.pillView.frame.isEmpty {
            self.pillView._change(pos: pillFrame.origin, animated: true, duration: 0.35, timingFunction: .spring)
            self.pillView._change(size: pillFrame.size, animated: true, duration: 0.35, timingFunction: .spring)
        } else {
            self.pillView.frame = pillFrame
        }
        self.detailView.frame = CGRect(x: padding, y: 0, width: max(pillWidth - padding * 2, 0), height: pillHeight)
    }
}
