import Cocoa
import TGUIKit
import GraphCore

class ChartView: Control {
    required init(frame: CGRect) {
        super.init(frame: frame)
        
        setupView()
        
        set(handler: { [weak self] _ in
            self?.userWantZoomIfPossible?()
        }, for: .Click)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        setupView()
    }
    
    var chartInsets: NSEdgeInsets = NSEdgeInsets(top: 40, left: 16, bottom: 35, right: 16) {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var renderers: [ChartViewRenderer] = [] {
        willSet {
            renderers.forEach { $0.containerViews.removeAll(where: { $0.value == self || $0.value == nil }) }
        }
        didSet {
            renderers.forEach { $0.containerViews.append(ContainerViewReference(value: self)) }
            setNeedsDisplay()
        }
    }
    
    var chartFrame: CGRect {
        let chartBound = self.bounds
        return CGRect(x: chartInsets.left,
                      y: chartInsets.top,
                      width: max(1, chartBound.width - chartInsets.left - chartInsets.right),
                      height: max(1, chartBound.height - chartInsets.top - chartInsets.bottom))
    }
    
    private var revealProgress: CGFloat = 1
    private var revealStart: CFTimeInterval = 0
    private var revealDuration: CFTimeInterval = 0.8
    private var revealLink: AnyObject?
    private var revealTimer: Timer?
    
    func playReveal(duration: CFTimeInterval = 0.8, delay: CFTimeInterval = 0) {
        guard self.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, self.renderers.contains(where: { $0.revealKind != .none }) else {
            return
        }
        self.revealDuration = duration
        self.revealStart = CACurrentMediaTime() + delay
        self.revealProgress = 0
        self.setNeedsDisplay()
        if #available(macOS 14.0, *) {
            if self.revealLink == nil {
                let link = self.displayLink(target: self, selector: #selector(self.revealTick))
                link.add(to: .main, forMode: .common)
                self.revealLink = link
            }
        } else if self.revealTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(self.revealTick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self.revealTimer = timer
        }
    }
    
    func finishReveal() {
        self.stopRevealDriver()
        if self.revealProgress < 1 {
            self.revealProgress = 1
            self.setNeedsDisplay()
        }
    }
    
    private func stopRevealDriver() {
        if #available(macOS 14.0, *), let link = self.revealLink as? CADisplayLink {
            link.invalidate()
        }
        self.revealLink = nil
        self.revealTimer?.invalidate()
        self.revealTimer = nil
    }
    
    @objc private func revealTick() {
        let elapsed = CACurrentMediaTime() - self.revealStart
        if elapsed < 0 {
            return
        }
        let t = min(1, elapsed / self.revealDuration)
        self.revealProgress = CGFloat(1 - pow(1 - t, 3))
        self.setNeedsDisplay()
        if t >= 1 {
            self.stopRevealDriver()
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window == nil {
            self.finishReveal()
        }
    }
    
    private func clipReveal(_ kind: ChartRevealKind, context: CGContext, bounds: CGRect, chartFrame: CGRect) {
        let progress = self.revealProgress
        switch kind {
        case .none:
            break
        case .horizontal:
            let maxX = chartFrame.minX + (chartFrame.width + 4) * progress
            context.clip(to: CGRect(x: bounds.minX, y: bounds.minY, width: max(0, maxX - bounds.minX), height: bounds.height))
        case .vertical:
            let minY = chartFrame.maxY - (chartFrame.height + 4) * progress
            context.clip(to: CGRect(x: bounds.minX, y: minY, width: bounds.width, height: max(0, bounds.maxY - minY)))
        case .radial:
            let center = CGPoint(x: chartFrame.midX, y: chartFrame.midY)
            let radius = hypot(bounds.width, bounds.height)
            let start = -CGFloat.pi / 2
            let path = CGMutablePath()
            path.move(to: center)
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: start + CGFloat.pi * 2 * progress, clockwise: false)
            path.closeSubpath()
            context.addPath(path)
            context.clip()
        }
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let chartBounds = self.bounds
        let chartFrame = self.chartFrame
        let revealing = self.revealProgress < 1
        
        for renderer in renderers {
            let kind = revealing ? renderer.revealKind : .none
            if kind == .none {
                renderer.render(context: ctx, bounds: chartBounds, chartFrame: chartFrame)
            } else {
                ctx.saveGState()
                self.clipReveal(kind, context: ctx, bounds: chartBounds, chartFrame: chartFrame)
                renderer.render(context: ctx, bounds: chartBounds, chartFrame: chartFrame)
                ctx.restoreGState()
            }
        }
    }
    
    var userDidSelectCoordinateClosure: ((CGPoint) -> Void)?
    var userDidDeselectCoordinateClosure: (() -> Void)?
    
    var userWantZoomIfPossible: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        updateMouse()
    }
    
    func updateMouse() {
        if let event = window?.currentEvent {
            let point = convert(event.locationInWindow, from: nil)
            
            let fractionPoint = CGPoint(x: (point.x - chartFrame.origin.x) / chartFrame.width,
                                        y: (point.y - chartFrame.origin.y) / chartFrame.height)
            
            if NSPointInRect(point, frame) {
                userDidSelectCoordinateClosure?(fractionPoint)
            } else {
                userDidDeselectCoordinateClosure?()
            }
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateMouse()
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateMouse()
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateMouse()
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        updateMouse()
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        //updateMouse()
    }
    
    // MARK: Details View
    
    var chartStyle: ChartStyle = .classic {
        didSet {
            self.detailsView?.chartStyle = self.chartStyle
        }
    }
    
    private var detailsView: ChartDetailsView!
    private var maxDetailsViewWidth: CGFloat = 0
    func loadDetailsViewIfNeeded() {
        if detailsView == nil {
            let detailsView = ChartDetailsView(frame: bounds)
            detailsView.chartStyle = self.chartStyle
            addSubview(detailsView)
            detailsView.alphaValue = 0
            self.detailsView = detailsView
        }
    }
    
    private var detailsTableTopOffset: CGFloat = 5
    private var detailsTableLeftOffset: CGFloat = 8
    private var isDetailsViewVisible: Bool = false

    var detailsViewPosition: CGFloat = 0 {
        didSet {
            loadDetailsViewIfNeeded()
            let detailsViewSize = detailsView.intrinsicContentSize
            maxDetailsViewWidth = max(maxDetailsViewWidth, detailsViewSize.width)
            if maxDetailsViewWidth + detailsTableLeftOffset > detailsViewPosition {
                detailsView.frame = CGRect(x: floorToScreenPixels(System.backingScale, min(detailsViewPosition + detailsTableLeftOffset, bounds.width - maxDetailsViewWidth)),
                                           y: floorToScreenPixels(System.backingScale, chartInsets.top + detailsTableTopOffset),
                                           width: maxDetailsViewWidth,
                                           height: detailsViewSize.height)
            } else {
                detailsView.frame = CGRect(x: floorToScreenPixels(System.backingScale, detailsViewPosition - maxDetailsViewWidth - detailsTableLeftOffset),
                                           y: floorToScreenPixels(System.backingScale, chartInsets.top + detailsTableTopOffset),
                                           width: maxDetailsViewWidth,
                                           height: detailsViewSize.height)
            }
        }
    }
    
    func setDetailsChartVisible(_ visible: Bool, animated: Bool) {
        guard isDetailsViewVisible != visible else {
            return
        }
        isDetailsViewVisible = visible
        loadDetailsViewIfNeeded()
        detailsView.setVisible(visible, animated: animated)
        if !visible {
            maxDetailsViewWidth = 0
        }
    }
    
    func setDetailsViewModel(viewModel: ChartDetailsViewModel, animated: Bool) {
        loadDetailsViewIfNeeded()
        detailsView.setup(viewModel: viewModel, animated: animated)
        View.perform(animated: animated, animations: {
            let position = self.detailsViewPosition
            self.detailsViewPosition = position
        })
    }

    func setupView() {
        backgroundColor = .clear
        layer?.drawsAsynchronously = true
    }
}


extension ChartView: ChartThemeContainer {
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        detailsView?.apply(theme: theme, strings: strings, animated: animated && (detailsView?.isVisibleInWindow ?? false))
    }
}
