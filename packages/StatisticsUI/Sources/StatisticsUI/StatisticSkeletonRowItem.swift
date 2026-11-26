import Cocoa
import TGUIKit
import GeneralRows
import InputDataUI
import TelegramTheme
import ColorPalette
import GraphUI
import Localization

public final class StatisticSkeletonRowItem: GeneralRowItem {
    let seriesCount: Int
    private var chartHeight: CGFloat = 308

    public init(_ initialSize: NSSize, stableId: AnyHashable, seriesCount: Int, viewType: GeneralViewType) {
        self.seriesCount = seriesCount
        super.init(initialSize, stableId: stableId, viewType: viewType)
        _ = self.makeSize(initialSize.width, oldWidth: 0)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.chartHeight = ChartSkeletonView.chartHeight(width: self.blockWidth - self.viewType.innerInset.left - self.viewType.innerInset.right, seriesCount: self.seriesCount)
        return true
    }

    public override var height: CGFloat {
        return self.chartHeight + self.viewType.innerInset.top + self.viewType.innerInset.bottom
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonLoading
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override var instantlyResize: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return StatisticRowView.self
    }
}

public final class StatisticSkeletonListRowItem: GeneralRowItem {
    public enum Style {
        case amount
        case avatar
        case balance
        case level
    }

    fileprivate let style: Style
    private let heightProvider: ((CGFloat) -> CGFloat)?
    private var computedHeight: CGFloat = 50

    public init(_ initialSize: NSSize, stableId: AnyHashable, style: Style, viewType: GeneralViewType, heightProvider: ((CGFloat) -> CGFloat)? = nil) {
        self.style = style
        self.heightProvider = heightProvider
        super.init(initialSize, stableId: stableId, viewType: viewType)
        _ = self.makeSize(initialSize.width, oldWidth: 0)
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonLoading
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    fileprivate static func lineHeight(_ font: NSFont) -> CGFloat {
        let layout = TextViewLayout(.initialize(string: "0", color: .black, font: font), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        return layout.layoutSize.height
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        if let heightProvider = self.heightProvider {
            self.computedHeight = heightProvider(width)
            return true
        }
        switch self.style {
        case .amount:
            self.computedHeight = self.viewType.innerInset.top + StatisticSkeletonListRowItem.lineHeight(.medium(.header)) + 2 + StatisticSkeletonListRowItem.lineHeight(.normal(.text)) + self.viewType.innerInset.bottom
        case .avatar:
            self.computedHeight = 50
        case .balance:
            self.computedHeight = self.viewType.innerInset.top + 43 + StatisticSkeletonListRowItem.lineHeight(.normal(.text)) + self.viewType.innerInset.top + 50 + self.viewType.innerInset.left
        case .level:
            self.computedHeight = 100
        }
        return true
    }

    public override var height: CGFloat {
        return self.computedHeight
    }

    public override var instantlyResize: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return StatisticSkeletonListRowView.self
    }

    fileprivate var drawsCard: Bool {
        return self.style != .level
    }

    fileprivate func shapes(width: CGFloat, height: CGFloat) -> [ChartSkeletonView.Shape] {
        let left = self.viewType.innerInset.left
        let right = width - self.viewType.innerInset.right
        let top = self.viewType.innerInset.top
        switch self.style {
        case .amount:
            let amountHeight = StatisticSkeletonListRowItem.lineHeight(.medium(.header))
            return [
                .roundedRect(CGRect(x: left, y: top + floor((amountHeight - 16) / 2), width: min(150, right - left), height: 16), cornerRadius: 6),
                .roundedRect(CGRect(x: left, y: top + amountHeight + 2 + 3, width: min(96, right - left), height: 10), cornerRadius: 5)
            ]
        case .avatar:
            let titleWidth = max(40, (right - left - 46) * 0.42)
            return [
                .roundedRect(CGRect(x: left, y: 7, width: 36, height: 36), cornerRadius: 18),
                .roundedRect(CGRect(x: left + 46, y: 11, width: titleWidth, height: 11), cornerRadius: 5.5),
                .roundedRect(CGRect(x: left + 46, y: 29, width: titleWidth * 0.6, height: 9), cornerRadius: 4.5),
                .roundedRect(CGRect(x: right - 58, y: 19, width: 58, height: 11), cornerRadius: 5.5)
            ]
        case .balance:
            let center = width / 2
            return [
                .roundedRect(CGRect(x: center - 80, y: top + 8, width: 160, height: 30), cornerRadius: 10),
                .roundedRect(CGRect(x: center - 45, y: top + 46, width: 90, height: 10), cornerRadius: 5),
                .roundedRect(CGRect(x: left, y: height - self.viewType.innerInset.left - 10 - 40, width: right - left, height: 40), cornerRadius: 10)
            ]
        case .level:
            let center = width / 2
            let lineWidth = min(600, width - 40)
            let lineLeft = floor((width - lineWidth) / 2)
            return [
                .roundedRect(CGRect(x: center - 44, y: 6, width: 88, height: 30), cornerRadius: 15),
                .roundedRect(CGRect(x: lineLeft, y: 52, width: lineWidth, height: 30), cornerRadius: 10)
            ]
        }
    }
}

private final class StatisticSkeletonListRowView: GeneralContainableRowView {
    private let skeletonView = ChartSkeletonView(frame: NSZeroRect)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(self.skeletonView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let item = self.item as? StatisticSkeletonListRowItem else {
            return
        }
        if item.drawsCard {
            self.skeletonView.frame = self.containerView.bounds
        } else {
            self.skeletonView.frame = NSMakeRect(-self.containerView.frame.minX, 0, self.frame.width, self.containerView.frame.height)
        }
        self.updateSkeleton()
    }

    override func updateColors() {
        super.updateColors()
        if let item = self.item as? StatisticSkeletonListRowItem, !item.drawsCard {
            self.containerView.backgroundColor = .clear
        }
        self.updateSkeleton()
    }

    private func updateSkeleton() {
        guard let item = self.item as? StatisticSkeletonListRowItem else {
            return
        }
        let colors = ChartSkeletonView.colors(isDark: theme.colors.isDark)
        self.skeletonView.update(shapes: item.shapes(width: self.skeletonView.frame.width, height: self.skeletonView.frame.height), baseColor: colors.base, highlightColor: colors.highlight)
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        self.needsLayout = true
    }
}

public typealias StatisticSkeletonGraph = (identifier: InputDataIdentifier, title: String, seriesCount: Int)

func statisticsSkeletonEntries(overviewTitle: String, overviewCount: Int = 4, graphs: [StatisticSkeletonGraph]) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(overviewTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("overview"), equatable: InputDataEquatable("skeleton"), comparable: nil, item: { initialSize, stableId in
        return ChannelOverviewStatsRowItem(initialSize, stableId: stableId, skeletonCount: overviewCount, viewType: .singleItem)
    }))
    index += 1
    entries.append(contentsOf: statisticsGraphSkeletonEntries(graphs, sectionId: &sectionId, index: &index))
    return entries
}

public func statisticsGraphSkeletonEntries(_ graphs: [StatisticSkeletonGraph], sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    for graph in graphs {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(graph.title), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        let seriesCount = graph.seriesCount
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable("skeleton"), comparable: nil, item: { initialSize, stableId in
            return StatisticSkeletonRowItem(initialSize, stableId: stableId, seriesCount: seriesCount, viewType: .singleItem)
        }))
        index += 1
    }
    return entries
}

public func statisticsListSkeletonEntries(prefix: String, count: Int, style: StatisticSkeletonListRowItem.Style = .avatar, sectionId: Int32, index: inout Int32) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    for i in 0 ..< count {
        let viewType: GeneralViewType
        if count == 1 {
            viewType = .singleItem
        } else if i == 0 {
            viewType = .firstItem
        } else if i == count - 1 {
            viewType = .lastItem
        } else {
            viewType = .innerItem
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("_skeleton_\(prefix)_\(i)"), equatable: InputDataEquatable("skeleton"), comparable: nil, item: { initialSize, stableId in
            return StatisticSkeletonListRowItem(initialSize, stableId: stableId, style: style, viewType: viewType)
        }))
        index += 1
    }
    return entries
}

public func statisticsGraphPlaceholderItem(_ initialSize: NSSize, stableId: AnyHashable, seriesCount: Int) -> TableRowItem {
    if statisticsChartStyle.usesGlass {
        return StatisticSkeletonRowItem(initialSize, stableId: stableId, seriesCount: seriesCount, viewType: .singleItem)
    }
    return StatisticLoadingRowItem(initialSize, stableId: stableId, error: nil)
}
