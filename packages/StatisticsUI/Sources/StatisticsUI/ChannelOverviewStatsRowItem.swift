import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore

import GraphCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AvatarUI
import ShortPeerRow
import LocalAnimations
import GraphUI
import DateUtils
import TelegramIconsTheme
import TelegramMediaUtils
import MessageTextUtils

public struct ChannelOverviewItem : Equatable {
    public let title: String
    public let value: NSAttributedString

    public init(title: String, value: NSAttributedString) {
        self.title = title
        self.value = value
    }
}

public extension StatsValue {
    var attributedString: NSAttributedString {
        
        let deltaValue = self.current - self.previous
        let deltaCompact = abs(Int(deltaValue)).prettyNumber
        var delta = deltaValue == 0 ? "" : deltaValue > 0 ? " +\(deltaCompact)" : " -\(deltaCompact)"
        var deltaPercentage = 0.0
        if self.previous > 0.0, deltaValue != 0 {
            deltaPercentage = abs(deltaValue / self.previous)
            delta += String(format: " (%.02f%%)", deltaPercentage * 100)
        }
        
        let attr = NSMutableAttributedString()
        
        _ = attr.append(string: Int(self.current).prettyNumber, color: theme.colors.text, font: .medium(.header))
        if !delta.isEmpty {
            _ = attr.append(string: delta, color: deltaValue < 0 ? theme.colors.redUI : theme.colors.greenUI, font: .normal(.small))
        }
        
        return attr

    }
}
public extension StatsPercentValue {
    var attributedString: NSAttributedString {
        let attr = NSMutableAttributedString()

        let deltaPercentage = abs(self.value / self.total)

        _ = attr.append(string: String(format: "%.02f%%", deltaPercentage * 100), color: theme.colors.text, font: .medium(.header))
        
        return attr
    }
}

private let overviewTileSpacing: CGFloat = 8

private struct ChannelOverviewTileItem {
    let content: ChartOverviewTileView.Content
    let height: CGFloat

    init(item: ChannelOverviewItem) {
        var runs: [(String, NSColor?)] = []
        let string = item.value
        string.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: string.length), options: []) { value, range, _ in
            runs.append((string.attributedSubstring(from: range).string, value as? NSColor))
        }
        let value = runs.first?.0.trimmingCharacters(in: .whitespaces) ?? ""
        let detail = runs.dropFirst().map(\.0).joined().trimmingCharacters(in: .whitespaces)
        let detailColor = runs.dropFirst().first?.1 ?? theme.colors.grayText
        let tinted = detailColor == theme.colors.greenUI || detailColor == theme.colors.redUI
        self.content = ChartOverviewTileView.Content(title: item.title, value: value, detail: detail, titleColor: theme.colors.grayText, valueColor: theme.colors.text, detailColor: tinted ? detailColor : theme.colors.grayText, detailTinted: tinted)
        self.height = ChartOverviewTileView.height(for: self.content)
    }
}

private struct ChannelOverviewLayoutItem {
    public let title: TextViewLayout
    public let name: TextViewLayout
    
    public init(item: ChannelOverviewItem) {
        self.name = TextViewLayout(.initialize(string: item.title, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        
        self.title = TextViewLayout(item.value, maximumNumberOfLines: 1)
    }
    
    public func measure(_ width: CGFloat) {
        self.title.measure(width: width)
        self.name.measure(width: width)
    }
    
    public var size: NSSize {
        return NSMakeSize(max(self.title.layoutSize.width, self.name.layoutSize.width), title.layoutSize.height + 3 + name.layoutSize.height)
    }
}

public class ChannelOverviewStatsRowItem: GeneralRowItem {
    
    
    fileprivate let layoutItems:[ChannelOverviewLayoutItem]
    fileprivate let tileItems: [ChannelOverviewTileItem]
    fileprivate let usesGlass: Bool
    fileprivate let isSkeleton: Bool
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, items: [ChannelOverviewItem], viewType: GeneralViewType) {
        self.layoutItems = items.map {
            return ChannelOverviewLayoutItem(item: $0)
        }
        self.usesGlass = statisticsChartStyle.usesGlass
        self.isSkeleton = false
        self.tileItems = self.usesGlass ? items.map(ChannelOverviewTileItem.init) : []
        super.init(initialSize, stableId: stableId, viewType: viewType)
        
        _ = makeSize(initialSize.width)
    }
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, skeletonCount: Int, viewType: GeneralViewType) {
        let placeholders = (0 ..< skeletonCount).map { _ in ChannelOverviewItem(title: " ", value: .initialize(string: "0", color: theme.colors.text, font: .medium(.header))) }
        self.layoutItems = []
        self.usesGlass = true
        self.isSkeleton = true
        self.tileItems = placeholders.map(ChannelOverviewTileItem.init)
        super.init(initialSize, stableId: stableId, viewType: viewType)
        
        _ = makeSize(initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        for item in layoutItems {
            item.measure((blockWidth - viewType.innerInset.left - viewType.innerInset.right - 20) / 2)
        }
        
        return true
    }
    
    fileprivate func tileRowHeight(_ row: Int) -> CGFloat {
        let first = row * 2
        let last = min(first + 1, self.tileItems.count - 1)
        return self.tileItems[first ... last].map(\.height).max() ?? 0
    }
    
    fileprivate var tileRowCount: Int {
        return (self.tileItems.count + 1) / 2
    }
    
    public override var height: CGFloat {
        if self.usesGlass {
            let rows = self.tileRowCount
            let tiles = (0 ..< rows).reduce(0) { $0 + self.tileRowHeight($1) }
            return tiles + CGFloat(max(rows - 1, 0)) * overviewTileSpacing + self.inset.top + self.inset.bottom
        }
        
        var height: CGFloat = 0
        
        for (i, item) in layoutItems.enumerated() {
            if i % 2 == 0 {
                height += item.size.height
                if i < layoutItems.count - 2 {
                    height += 10
                }
            }
        }
        
        return height + viewType.innerInset.bottom + viewType.innerInset.top
    }
    
    public override var accessibilityLabel: String? {
        return isSkeleton ? strings().voiceOverCommonLoading : strings().channelStatsOverview
    }

    public override var accessibilityValue: String? {
        if isSkeleton {
            return nil
        }
        return layoutItems.map { "\($0.name.attributedString.string): \($0.title.attributedString.string)" }.joined(separator: ", ")
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return ChannelOverviewStatsRowView.self
    }
}

private final class ChannelOverviewLayoutView : View {
    private let titleView: TextView = TextView()
    private let nameView: TextView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(nameView)
        
        nameView.isSelectable = false
        nameView.userInteractionEnabled = false
    }
    
    public override func layout() {
        super.layout()
        self.titleView.setFrameOrigin(.zero)
        self.nameView.setFrameOrigin(NSMakePoint(0, self.titleView.frame.maxY + 3))
    }
    
    public func update(_ item: ChannelOverviewLayoutItem) {
        self.titleView.update(item.title)
        self.nameView.update(item.name)
        needsLayout = true
    }
    
    public func updateColors() {
        
        let backgroundColor = theme.colors.background
        
        self.backgroundColor = backgroundColor
        self.titleView.backgroundColor = backgroundColor
        self.nameView.backgroundColor = backgroundColor
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder :) has not been implemented")
    }
}

private final class ChannelOverviewStatsRowView : TableRowView {
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private var tiles: [ChartOverviewTileView] = []
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(self.containerView)
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? ChannelOverviewStatsRowItem else {
            return
        }
        
        if item.usesGlass {
            let originX = floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2)
            let tileWidth = floorToScreenPixels(backingScaleFactor, (item.blockWidth - overviewTileSpacing) / 2)
            var y = item.inset.top
            for row in 0 ..< item.tileRowCount {
                let height = item.tileRowHeight(row)
                for column in 0 ..< 2 {
                    let index = row * 2 + column
                    guard index < self.tiles.count else {
                        break
                    }
                    let x = column == 0 ? originX : originX + item.blockWidth - tileWidth
                    self.tiles[index].frame = NSMakeRect(x, y, tileWidth, height)
                }
                y += height + overviewTileSpacing
            }
            return
        }
        
        self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
        self.containerView.setCorners(item.viewType.corners)
        
        
        var point: CGPoint = NSMakePoint(item.viewType.innerInset.left, item.viewType.innerInset.top)
        for (i, subview) in self.containerView.subviews.enumerated() {
            subview.setFrameOrigin(point)
            if i < self.containerView.subviews.count - 1 {
                if (i + 1) % 2 == 0 {
                    point.x = item.viewType.innerInset.left
                    point.y += self.containerView.subviews[i + 1].frame.height
                    if i < self.containerView.subviews.count - 1  {
                        point.y += 10
                    }
                } else {
                    var width: CGFloat = self.containerView.subviews[i + 1].frame.width
                    if i > 1 {
                        width = max(width, self.containerView.subviews[i - 1].frame.width)
                    }
                    if i + 3 < self.containerView.subviews.count {
                        width = max(width, self.containerView.subviews[i + 3].frame.width)
                    }
                    
                    point.x = self.containerView.frame.width - width - item.viewType.innerInset.right
                   
                }
            }
            
        }
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func updateColors() {
        guard let item = item as? ChannelOverviewStatsRowItem else {
            return
        }
        self.backgroundColor = item.viewType.rowBackground
        self.containerView.backgroundColor = backdorColor
        if item.usesGlass {
            for (tile, tileItem) in zip(self.tiles, item.tileItems) {
                if item.isSkeleton {
                    tile.showSkeleton(cardColor: theme.colors.background, isDark: theme.colors.isDark)
                } else {
                    tile.update(content: tileItem.content, cardColor: theme.colors.background, isDark: theme.colors.isDark, animated: false)
                }
            }
        }
        
        for subview in self.containerView.subviews {
            (subview as? ChannelOverviewLayoutView)?.updateColors()
        }
    }
    
    
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        let previousStableId = self.item?.stableId
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? ChannelOverviewStatsRowItem else {
            return
        }
        
        if item.usesGlass {
            self.containerView.isHidden = true
            self.containerView.removeAllSubviews()
            let sameRow = previousStableId == item.stableId
            let revealing = sameRow && self.tiles.contains(where: { $0.isSkeleton })
            let morphs = sameRow && (revealing || self.tiles.count == item.tileItems.count)
            while self.tiles.count > item.tileItems.count {
                self.tiles.removeLast().removeFromSuperview()
            }
            while self.tiles.count < item.tileItems.count {
                let tile = ChartOverviewTileView(frame: .zero)
                self.addSubview(tile)
                self.tiles.append(tile)
                if revealing {
                    tile.showSkeleton(cardColor: theme.colors.background, isDark: theme.colors.isDark)
                }
            }
            for (tile, tileItem) in zip(self.tiles, item.tileItems) {
                if item.isSkeleton {
                    tile.showSkeleton(cardColor: theme.colors.background, isDark: theme.colors.isDark)
                } else {
                    tile.update(content: tileItem.content, cardColor: theme.colors.background, isDark: theme.colors.isDark, animated: morphs)
                }
            }
            needsLayout = true
            return
        }
        self.containerView.isHidden = false
        self.tiles.forEach { $0.removeFromSuperview() }
        self.tiles.removeAll()
        self.containerView.removeAllSubviews()
        
        for item in item.layoutItems {
            let view = ChannelOverviewLayoutView(frame: CGRect(origin: .zero, size: item.size))
            view.update(item)
            self.containerView.addSubview(view)
        }
        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}


