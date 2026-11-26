import Cocoa
import TGUIKit
import TelegramTheme
import Localization

final class SearchShimmerRowItem: TableRowItem {
    override var height: CGFloat {
        return remainingTableHeight(for: self)
    }

    override func viewClass() -> AnyClass {
        return SearchShimmerRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonLoading
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

final class SearchShimmerView: View {
    private let shimmer = ShimmerEffectView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        shimmer.isEventLess = true
        addSubview(shimmer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: NSSize) {
        let bounds = size.bounds
        shimmer.frame = bounds
        shimmer.updateAbsoluteRect(bounds, within: size)
        shimmer.update(backgroundColor: theme.colors.background, foregroundColor: theme.colors.grayBackground, shimmeringColor: theme.colors.background.withAlphaComponent(0.4), shapes: shapes(for: size), horizontal: false, size: size)
    }

    private func shapes(for size: NSSize) -> [ShimmerEffectView.Shape] {
        let rowHeight: CGFloat = 70
        let leftInset: CGFloat = 70
        let margin: CGFloat = 9
        let lineHeight: CGFloat = 8
        let titleY: CGFloat = 12

        var shapes: [ShimmerEffectView.Shape] = []

        func line(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat) {
            let width = min(width, size.width - margin - x)
            if width >= lineHeight {
                shapes.append(.roundedRectLine(startPoint: NSMakePoint(x, y), width: width, diameter: lineHeight))
            }
        }

        var y: CGFloat = 0
        while y < size.height {
            shapes.append(.circle(NSMakeRect(10, y + 10, 50, 50)))
            line(leftInset, y + titleY, 60)
            line(leftInset, y + floor((rowHeight - lineHeight) / 2), 120)
            line(leftInset + 130, y + floor((rowHeight - lineHeight) / 2), 60)
            line(leftInset, y + rowHeight - titleY - lineHeight, 60)
            line(size.width - margin - 30, y + margin, 30)
            shapes.append(.rect(rect: NSMakeRect(leftInset, y + rowHeight - .borderSize, max(0, size.width - leftInset), .borderSize)))
            y += rowHeight
        }
        return shapes
    }
}

private final class SearchShimmerRowView: TableRowView {
    private let shimmerView = SearchShimmerView(frame: .zero)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(shimmerView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        shimmerView.frame = bounds
        shimmerView.update(size: bounds.size)
    }
}
