import Cocoa
import TGUIKit
import GraphUI
import GraphCore
import SwiftSignalKit
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
import DateUtils
import TelegramIconsTheme
import TelegramCore
import Postbox
import TelegramMediaUtils
import MessageTextUtils
public enum ChartItemType {
    case lines
    case twoAxis
    case pie
    case area
    case bars
    case step
    case twoAxisStep
    case hourlyStep
    case twoAxisHourlyStep
    case twoAxis5MinStep
    case currency(String)
}

private func drawTonSymbol(context: CGContext, color: UIColor, at point: CGPoint) {
    let width: CGFloat = 8.0
    let height: CGFloat = 7.5
    let cornerRadius: CGFloat = 0.5
    
    let topPoint = CGPoint(x: point.x + width / 2, y: point.y)
    let bottomPoint = CGPoint(x: point.x + width / 2, y: point.y + height)
    let leftTopPoint = CGPoint(x: point.x, y: point.y)
    let rightTopPoint = CGPoint(x: point.x + width, y: point.y)
    
    context.saveGState()
    
    context.beginPath()
    context.move(to: CGPoint(x: leftTopPoint.x + cornerRadius, y: leftTopPoint.y))
    
    context.addArc(tangent1End: leftTopPoint, tangent2End: bottomPoint, radius: cornerRadius)
    context.addLine(to: CGPoint(x: bottomPoint.x, y: bottomPoint.y - cornerRadius + GView.oneDevicePixel))
    
    context.move(to: CGPoint(x: rightTopPoint.x - cornerRadius, y: rightTopPoint.y))
    context.addArc(tangent1End: rightTopPoint, tangent2End: bottomPoint, radius: cornerRadius)
    context.addLine(to: CGPoint(x: bottomPoint.x, y: bottomPoint.y - cornerRadius + GView.oneDevicePixel))
                      
    context.move(to: CGPoint(x: leftTopPoint.x + cornerRadius, y: leftTopPoint.y))
    context.addLine(to: CGPoint(x: rightTopPoint.x - cornerRadius, y: rightTopPoint.y))
    
    context.move(to: topPoint)
    context.addLine(to: CGPoint(x: bottomPoint.x, y: bottomPoint.y - 1.0))
    
    context.setLineWidth(1.0)
    context.setLineCap(.round)
    context.setFillColor(UIColor.clear.cgColor)
    context.setStrokeColor(color.withAlphaComponent(1.0).cgColor)
    
    context.setAlpha(color.alphaValue)
    context.strokePath()
    
    context.restoreGState()
}


public class StatisticRowItem: GeneralRowItem {
    public let collection: ChartsCollection
    public let controller: BaseChartController
    fileprivate var revealed = false
    public let title: String?
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, collection: ChartsCollection, viewType: GeneralViewType, type: ChartItemType, rate: Double = 1.0, title: String? = nil, getDetailsData: @escaping (Date, @escaping (String?) -> Void) -> Void) {
        self.collection = collection
        self.title = title
        
        let controller: BaseChartController
        switch type {
        case .lines:
            controller = GeneralLinesChartController(chartsCollection: collection)
            controller.isZoomable = false
        case .twoAxis:
            controller = TwoAxisLinesChartController(chartsCollection: collection)
            controller.isZoomable = false
        case .pie:
            controller = PercentPieChartController(chartsCollection: collection)
        case .area:
            controller = PercentPieChartController(chartsCollection: collection, initiallyZoomed: false)
        case .bars:
            controller = StackedBarsChartController(chartsCollection: collection)
            controller.isZoomable = false
        case let .currency(value):
            let graphCurrency = GraphCurrency(rawValue: value)!
            controller = StackedBarsChartController(chartsCollection: collection, currency: graphCurrency, drawCurrency: { context, color, point in
                switch graphCurrency {
                case .xtr:
                    let image = TelegramThemeHooks.shared.image(.iconStarCurrency).precomposed()
                    let size = image.backingSize
                    let point = point
                        
                    context.saveGState()
                    context.resetClip()
                    context.translateBy(x: point.x, y: point.y)
                    let angle: CGFloat = -35 * (.pi / 180)
                    context.rotate(by: angle)
                    context.translateBy(x: -point.x, y: -point.y)
                    context.concatenate(CGAffineTransform.identity)
                    context.draw(image, in: CGRect(origin: point.offsetBy(dx: -size.width/2, dy: -size.height/2 + 2), size: size))
                    context.restoreGState()
                case .ton:
                    drawTonSymbol(context: context, color: color, at: point)
                }
            }, rate: rate)
            controller.isZoomable = false
        case .step:
            controller = StepBarsChartController(chartsCollection: collection)
        case .twoAxisStep:
            controller = TwoAxisStepBarsChartController(chartsCollection: collection)
        case .hourlyStep:
            controller = StepBarsChartController(chartsCollection: collection, hourly: true)
            controller.isZoomable = false
        case .twoAxisHourlyStep:
            let stepController = TwoAxisStepBarsChartController(chartsCollection: collection)
            stepController.hourly = true
            controller = stepController
            controller.isZoomable = false
        case .twoAxis5MinStep:
            let stepController = TwoAxisStepBarsChartController(chartsCollection: collection)
            stepController.min5 = true
            controller = stepController
            controller.isZoomable = false
        }
        
        
        
        controller.getDetailsData = { date, completion in
            let signal:Signal<ChartsCollection?, NoError> = Signal { subscriber -> Disposable in
                var cancelled: Bool = false
                getDetailsData(date, { detailsData in
                    if let detailsData = detailsData, let data = detailsData.data(using: .utf8), !cancelled {
                        ChartsDataManager.readChart(data: data, extraCopiesCount: 0, sync: true, success: { collection in
                            if !cancelled {
                                subscriber.putNext(collection)
                                subscriber.putCompletion()
                            }
                           
                        }) { error in
                            if !cancelled {
                                subscriber.putNext(nil)
                                subscriber.putCompletion()
                            }
                        }
                    } else {
                        if !cancelled {
                            subscriber.putNext(nil)
                            subscriber.putCompletion()
                        }
                    }
                })
                
                return ActionDisposable {
                    cancelled = true
                }
            }
            
            _ = showModalProgress(signal: signal, for: context.window).start(next: { collection in
                completion(collection)
            })
        }
        self.controller = controller
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    private var graphHeight: CGFloat = 0
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        graphHeight = self.controller.height(for: blockWidth - (viewType.innerInset.left + viewType.innerInset.right)) + viewType.innerInset.bottom + viewType.innerInset.top
        return true
    }
    
    public override var height: CGFloat {
        return graphHeight
    }
    
    private var seriesNames: String? {
        let names = collection.chartValues.map { $0.name }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    public override var accessibilityLabel: String? {
        return title ?? seriesNames
    }

    public override var accessibilityValue: String? {
        return title != nil ? seriesNames : nil
    }

    public override func viewClass() -> AnyClass {
        return StatisticRowView.self
    }
    
    public override var instantlyResize: Bool {
        return false
    }
}
public class StatisticRowView: TableRowView {
    private let chartView: ChartStackSection = ChartStackSection()
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private var skeletonView: ChartSkeletonView?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(self.containerView)
        self.containerView.addSubview(chartView)
        self.chartView.chartStyle = statisticsChartStyle
    }
    
    public override func updateMouse(animated: Bool) {
        super.updateMouse(animated: animated)
        chartView.updateMouse()
    }
    
    private var chartTheme: ChartTheme {
        let chartTheme = (theme.colors.isDark ? ChartTheme.defaultNightTheme : ChartTheme.defaultDayTheme)
        return ChartTheme(chartTitleColor: theme.colors.text, actionButtonColor: theme.colors.accent, chartBackgroundColor: theme.colors.background, chartLabelsColor: theme.colors.grayText, chartHelperLinesColor: chartTheme.chartHelperLinesColor, chartStrongLinesColor: .random, barChartStrongLinesColor: chartTheme.barChartStrongLinesColor, chartDetailsTextColor: theme.colors.grayText, chartDetailsArrowColor: theme.colors.grayText, chartDetailsViewColor: theme.colors.grayBackground, rangeViewFrameColor: chartTheme.rangeViewFrameColor, rangeViewTintColor: theme.colors.grayForeground.withAlphaComponent(0.4), rangeViewMarkerColor: chartTheme.rangeViewTintColor, rangeCropImage: chartTheme.rangeCropImage)
    }
    
    public override var backdorColor: NSColor {
        return chartTheme.chartBackgroundColor
    }
    
    public override func updateColors() {
        guard let item = item as? GeneralRowItem else {
            return
        }
        self.backgroundColor = item.viewType.rowBackground
        self.containerView.backgroundColor = backdorColor
        self.updateSkeleton()
    }
    
    private func updateSkeleton() {
        guard let skeletonView = self.skeletonView, let item = self.item as? StatisticSkeletonRowItem else {
            return
        }
        let colors = ChartSkeletonView.colors(isDark: theme.colors.isDark)
        skeletonView.update(shapes: ChartSkeletonView.chartShapes(size: skeletonView.frame.size, seriesCount: item.seriesCount), baseColor: colors.base, highlightColor: colors.highlight)
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? GeneralRowItem else {
            return
        }
        
        self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
        self.containerView.setCorners(item.viewType.corners)
        
        let contentFrame = NSMakeRect(item.viewType.innerInset.left, item.viewType.innerInset.top, self.containerView.frame.width - item.viewType.innerInset.left - item.viewType.innerInset.right, self.containerView.frame.height - item.viewType.innerInset.top - item.viewType.innerInset.bottom)
        if let skeletonView = self.skeletonView {
            skeletonView.frame = contentFrame
            self.updateSkeleton()
        }
        guard item is StatisticRowItem else {
            return
        }
        chartView.frame = contentFrame
        chartView.layout()
    }
    
    private var pendingReveal = false
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.playPendingReveal()
    }
    
    private func playPendingReveal() {
        guard self.pendingReveal, self.window != nil else {
            return
        }
        self.pendingReveal = false
        self.chartView.playReveal()
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        if item is StatisticSkeletonRowItem {
            self.chartView.isHidden = true
            if self.skeletonView == nil {
                let skeletonView = ChartSkeletonView(frame: NSZeroRect)
                self.containerView.addSubview(skeletonView)
                self.skeletonView = skeletonView
            }
            self.needsLayout = true
            return
        }
        
        guard let item = item as? StatisticRowItem else {
            return
        }
        
        self.chartView.isHidden = false
        if let skeletonView = self.skeletonView {
            self.skeletonView = nil
            if self.window != nil {
                skeletonView.layer?.animateAlpha(from: 1, to: 0, duration: 0.14, removeOnCompletion: false, completion: { [weak skeletonView] _ in
                    skeletonView?.removeFromSuperview()
                })
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.22
                fade.beginTime = CACurrentMediaTime() + 0.08
                fade.fillMode = .backwards
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.chartView.layer?.add(fade, forKey: "skeletonHandoff")
            } else {
                skeletonView.removeFromSuperview()
            }
        }
        
        layout()
        
        chartView.setup(controller: item.controller, title: "Test")
        
        chartView.apply(theme: chartTheme, strings: ChartStrings(zoomOut: strings().graphZoomOut, total: strings().graphTotal, revenueInTon: strings().statsRevenueInTon, revenueInStars: strings().statsRevenueInStars, revenueInUsd: strings().statsRevenueInUsd), animated: false)
        
        if !item.revealed {
            item.revealed = true
            self.pendingReveal = true
            self.playPendingReveal()
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public class StatisticLoadingRowItem: GeneralRowItem {
    fileprivate let errorTextLayout: TextViewLayout?
    public init(_ initialSize: NSSize, stableId: AnyHashable, error: String?) {
        let height: CGFloat = 308 + GeneralViewType.singleItem.innerInset.bottom + GeneralViewType.singleItem.innerInset.top + 30
        if let error = error {
            self.errorTextLayout = TextViewLayout.init(.initialize(string: error, color: theme.colors.grayText, font: .normal(.text)))
        } else {
            self.errorTextLayout = nil
        }
        super.init(initialSize, height: height, stableId: stableId, viewType: .singleItem)
        _ = self.makeSize(initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        errorTextLayout?.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right)
        return true
    }
    
    public override var accessibilityLabel: String? {
        return errorTextLayout?.attributedString.string ?? strings().voiceOverCommonLoading
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return StatisticLoadingRowView.self
    }
    
    public override var instantlyResize: Bool {
        return false
    }
}
public class StatisticLoadingRowView: TableRowView {
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private var errorView: TextView?
    private var progressIndicator: ProgressIndicator?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(self.containerView)
        
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func updateColors() {
        guard let item = item as? StatisticLoadingRowItem else {
            return
        }
        self.backgroundColor = item.viewType.rowBackground
        self.containerView.backgroundColor = backdorColor
    }
    public override func layout() {
        super.layout()
        guard let item = item as? StatisticLoadingRowItem else {
            return
        }
        
        self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
        self.containerView.setCorners(item.viewType.corners)
        
        errorView?.center()
        progressIndicator?.center()
    }
    
    
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StatisticLoadingRowItem else {
            return
        }
        
        if let error = item.errorTextLayout {
            if self.errorView == nil {
                self.errorView = TextView()
                self.errorView?.isSelectable = false
                self.containerView.addSubview(self.errorView!)
                self.errorView?.center()
                if animated {
                    self.errorView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            if animated {
                if let progress = self.progressIndicator {
                    self.progressIndicator = nil
                    progress.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak progress] _ in
                        progress?.removeFromSuperview()
                    })
                }
            } else {
                self.progressIndicator?.removeFromSuperview()
                self.progressIndicator = nil
            }
            self.errorView?.update(error)
        } else {
            if self.progressIndicator == nil {
                self.progressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 30, 30))
                self.containerView.addSubview(self.progressIndicator!)
                self.errorView?.center()
                if animated {
                    self.progressIndicator?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            if animated {
                self.progressIndicator?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                if let errorView = self.errorView {
                    self.errorView = nil
                    errorView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak errorView] _ in
                        errorView?.removeFromSuperview()
                    })
                }
            } else {
                self.errorView?.removeFromSuperview()
                self.errorView = nil
            }
        }
        
        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
