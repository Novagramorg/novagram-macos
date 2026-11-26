import Cocoa
import TGUIKit
import GraphCore

private enum Constants {
    static let chartViewHeightFraction: CGFloat = 0.55
}

public class ChartStackSection: View, ChartThemeContainer {
    var chartView: ChartView
    var rangeView: RangeChartView
    var visibilityView: ChartVisibilityView
    var sectionContainerView: View
    var separators: [View] = []
    
    var headerLabel: NSTextField!
    var titleLabel: NSTextField!
    var backButton: TextButton!
    
    var controller: BaseChartController!
    
    private var backButtonGlass: LiquidGlassView?
    private var theme: ChartTheme = .defaultDayTheme
    
    public var chartStyle: ChartStyle = .classic {
        didSet {
            if oldValue != self.chartStyle {
                self.applyStyle()
            }
        }
    }
    
    private func applyStyle() {
        self.chartView.chartStyle = self.chartStyle
        self.rangeView.chartStyle = self.chartStyle
        self.visibilityView.chartStyle = self.chartStyle
        self.controller?.setLinesAreaFill(self.chartStyle.fillsLineArea)
        if self.chartStyle.usesGlass {
            if !self.backButton.isHidden && self.backButton.alphaValue > 0 {
                self.loadBackButtonGlassIfNeeded()
            }
        } else {
            self.backButtonGlass?.removeFromSuperview()
            self.backButtonGlass = nil
        }
        self.needsLayout = true
    }
    
    private func loadBackButtonGlassIfNeeded() {
        guard self.backButtonGlass == nil else {
            return
        }
        let glass = LiquidGlassView(frame: self.backButton.frame.insetBy(dx: -10, dy: -3), cornerRadius: 14, hasShadow: true, hasBorder: true, forceAppearance: self.theme.glassAppearance)
        glass.isEventLess = true
        self.addSubview(glass, positioned: .below, relativeTo: self.backButton)
        self.backButtonGlass = glass
    }
    
    override init() {
        sectionContainerView = View()
        chartView = ChartView(frame: NSZeroRect)
        rangeView = RangeChartView(frame: NSZeroRect)
        visibilityView = ChartVisibilityView()
        headerLabel = NSTextField()
        titleLabel = NSTextField()
        backButton = TextButton()
        
        super.init(frame: CGRect())
        
        self.addSubview(sectionContainerView)
        sectionContainerView.addSubview(chartView)
        sectionContainerView.addSubview(visibilityView)
        sectionContainerView.addSubview(rangeView)

        headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
       // visibilityView.clipsToBounds = true
     //   backButton.isExclusiveTouch = true
        
        backButton.setVisible(false, animated: false)
        
        headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
       // visibilityView.clipsToBounds = true
     //   backButton.isExclusiveTouch = true
        
        
        addSubview(titleLabel)
        addSubview(backButton)
        
        backButton.direction = .left
        _ = backButton.sizeToFit()
        backButton.set(handler: { [weak self] _ in
            self?.didTapBackButton()
        }, for: .Click)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        self.theme = theme
        self.visibilityView.apply(theme: theme, strings: strings, animated: animated)
        self.backButtonGlass?.forceAppearance = theme.glassAppearance
        View.perform(animated: animated && self.isVisibleInWindow) {
            self.backgroundColor = theme.chartBackgroundColor
            
            self.sectionContainerView.backgroundColor = theme.chartBackgroundColor
            self.rangeView.backgroundColor = theme.chartBackgroundColor
            self.visibilityView.backgroundColor = theme.chartBackgroundColor
         //  self.backButton.tintColor = theme.actionButtonColor
            self.backButton.set(color: theme.actionButtonColor, for: .Normal)
            
            self.backButton.set(text: "Zoom Out", for: .Normal)
            _ = self.backButton.sizeToFit()
            
            for separator in self.separators {
                separator.backgroundColor = theme.chartStrongLinesColor
            }
        }
        
        if rangeView.isVisibleInWindow || chartView.isVisibleInWindow {
            chartView.loadDetailsViewIfNeeded()
            chartView.apply(theme: theme, strings: strings, animated: animated && chartView.isVisibleInWindow)
            controller.apply(theme: theme, strings: strings, animated: animated)
            rangeView.apply(theme: theme, strings: strings, animated: animated && rangeView.isVisibleInWindow)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval.random(in: 0...0.1)) {
                self.chartView.loadDetailsViewIfNeeded()
                self.controller.apply(theme: theme, strings: strings, animated: false)
                self.chartView.apply(theme: theme, strings: strings, animated: false)
                self.rangeView.apply(theme: theme, strings: strings, animated: false)
            }
          
        }
        
        self.titleLabel.setTextColor(theme.chartTitleColor, animated: animated && titleLabel.isVisibleInWindow)
        self.headerLabel.setTextColor(theme.chartTitleColor, animated: animated && headerLabel.isVisibleInWindow)
        
        needsLayout = true
    }
    
     func didTapBackButton() {
        controller.didTapZoomOut()
    }
    
    public func playReveal() {
        self.chartView.playReveal(duration: 0.85)
        self.rangeView.chartView.playReveal(duration: 0.85, delay: 0.08)
        self.visibilityView.playReveal(delay: 0.2)
    }
    
    func setBackButtonVisible(_ visible: Bool, animated: Bool) {
        
        if visible && chartStyle.usesGlass {
            loadBackButtonGlassIfNeeded()
        }
        backButton.setVisible(visible, animated: animated)
        backButtonGlass?.isHidden = false
        backButtonGlass?.setVisible(visible, animated: animated)
        layoutIfNeeded(animated: animated)
    }
    
    func updateToolViews(animated: Bool) {
        rangeView.setRange(controller.currentChartHorizontalRangeFraction, animated: animated)
        rangeView.setRangePaging(enabled: controller.isChartRangePagingEnabled,
                                 minimumSize: controller.minimumSelectedChartRange)
        visibilityView.setVisible(controller.drawChartVisibity, animated: animated)
        if controller.drawChartVisibity {
            visibilityView.items = controller.actualChartsCollection.chartValues.map { value in
                return ChartVisibilityItem(title: value.name, color: value.color)
            }
            visibilityView.setItemsSelection(controller.actualChartVisibility)
            visibilityView.needsLayout = true
            visibilityView.layoutIfNeeded(animated: animated)
        }
    }
    
    override public func layout() {
        super.layout()
        
        let bounds = self.bounds
        self.titleLabel.frame = CGRect(origin: CGPoint(x: 0.0, y: 10.0), size: CGSize(width: bounds.width, height: 30))
        if self.chartStyle.usesGlass {
            self.backButton.frame = CGRect(origin: CGPoint(x: 12.0, y: 12.0), size: self.backButton.frame.size)
            self.backButtonGlass?.frame = self.backButton.frame.insetBy(dx: -10, dy: -3)
        } else {
            self.backButton.frame = CGRect(origin: CGPoint(x: 0.0, y: 10.0), size: self.backButton.frame.size)
        }
        
        self.sectionContainerView.frame = CGRect(origin: CGPoint(), size: CGSize(width: bounds.width, height: frame.height))
        self.chartView.frame = CGRect(origin: CGPoint(), size: CGSize(width: bounds.width, height: 250.0))
        self.rangeView.frame = CGRect(origin: CGPoint(x: 0.0, y: 250.0), size: CGSize(width: bounds.width, height: 48.0))
        let visibilityHeight = ChartVisibilityItem.generateItemsFrames(for: bounds.width, items: self.visibilityView.items).last?.maxY ?? 0
        self.visibilityView.frame = CGRect(origin: CGPoint(x: 0.0, y: 308.0), size: CGSize(width: bounds.width, height: visibilityHeight))
    }
    
    public func setup(controller: BaseChartController, title: String) {
        self.controller = controller
        self.headerLabel.setText(title, animated: false)
        
        // Chart
        chartView.renderers = controller.mainChartRenderers
        chartView.userDidSelectCoordinateClosure = { [unowned self] point in
            self.controller.chartInteractionDidBegin(point: point)
        }
        chartView.userDidDeselectCoordinateClosure = { [unowned self] in
            self.controller.cancelChartInteraction()
        }
        
        controller.cartViewBounds = { [unowned self] in
            return self.chartView.bounds
        }
        controller.chartFrame = { [unowned self] in
            return self.chartView.chartFrame
        }
        controller.setDetailsViewModel = { [unowned self] viewModel, animated, _ in
            self.chartView.setDetailsViewModel(viewModel: viewModel, animated: animated)
            
            self.chartView.userWantZoomIfPossible = {
                viewModel.tapAction?()
            }
        }
        controller.setDetailsChartVisibleClosure = { [unowned self] visible, animated in
            self.chartView.setDetailsChartVisible(visible, animated: animated)
        }
        controller.setDetailsViewPositionClosure = { [unowned self] position in
            self.chartView.detailsViewPosition = position
        }
        controller.setChartTitleClosure = { [unowned self] title, animated in
            self.titleLabel.setText(title, animated: animated)
        }
        controller.setBackButtonVisibilityClosure = { [unowned self] visible, animated in
            self.setBackButtonVisible(visible, animated: animated)
        }
        controller.refreshChartToolsClosure = { [unowned self] animated in
            self.updateToolViews(animated: animated)
        }
        
        // Range view
        rangeView.chartView.renderers = controller.navigationRenderers
        rangeView.rangeDidChangeClosure = { range in
            controller.updateChartRange(range)
        }
        rangeView.touchedOutsideClosure = {
            controller.cancelChartInteraction()
        }
        controller.chartRangeUpdatedClosure = { [unowned self] (range, animated) in
            self.rangeView.setRange(range, animated: animated)
        }
        controller.chartRangePagingClosure = {  [unowned self] (isEnabled, pageSize) in
            self.rangeView.setRangePaging(enabled: isEnabled, minimumSize: pageSize)
        }
        
        // Visibility view
        visibilityView.selectionCallbackClosure = { [unowned self] visibility in
            self.controller.updateChartsVisibility(visibility: visibility, animated: true)
        }
        
        controller.initializeChart()
        controller.setLinesAreaFill(self.chartStyle.fillsLineArea)
        updateToolViews(animated: false)
        
    }
    
    public func updateMouse() {
        self.chartView.updateMouse()
    }
}
