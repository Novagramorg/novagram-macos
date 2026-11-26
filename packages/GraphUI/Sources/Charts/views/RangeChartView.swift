import Cocoa
import TGUIKit
import GraphCore
private enum Constants {
    static let cropIndocatorLineWidth: CGFloat = 1
    static let markerSelectionRange: CGFloat = 25
    static let defaultMinimumRangeDistance: CGFloat = 0.05
    static let titntAreaWidth: CGFloat = 10
    static let horizontalContentMargin: CGFloat = 16
    static let cornerRadius: CGFloat = 5
    static let glassCornerRadius: CGFloat = 9
    static let glassFrameWidth: CGFloat = 1.5
    static let glassHandleWidth: CGFloat = 8
    static let glassHandleInset: CGFloat = 4
}

class RangeChartView: Control {
    private enum Marker {
        case lower
        case upper
        case center
    }
    public var lowerBound: CGFloat = 0 {
        didSet {
            needsLayout = true
        }
    }
    public var upperBound: CGFloat = 1 {
        didSet {
            needsLayout = true
        }
    }
    public var selectionColor: NSColor = .blue
    public var defaultColor: NSColor = .lightGray
    
    public var minimumRangeDistance: CGFloat = Constants.defaultMinimumRangeDistance
    
    private let lowerBoundTintView = View()
    private let upperBoundTintView = View()
    private let cropFrameView = TransparentImageView()
    
    private var selectedMarker: Marker?
    private var selectedMarkerHorizontalOffet: CGFloat = 0
    private var isBoundCropHighlighted: Bool = false
    private var isRangePagingEnabled: Bool = false
    
    public let chartView = ChartView(frame: NSZeroRect)
    
    private let selectionFrameView = View()
    private var glassHandles: [View] = []
    private var theme: ChartTheme = .defaultDayTheme
    
    var chartStyle: ChartStyle = .classic {
        didSet {
            if oldValue != self.chartStyle {
                self.applyStyle()
            }
        }
    }
    
    var layoutMargins: NSEdgeInsets
    
    required init(frame: CGRect) {
        layoutMargins = NSEdgeInsets(top: Constants.cropIndocatorLineWidth,
                                     left: Constants.horizontalContentMargin,
                                     bottom: Constants.cropIndocatorLineWidth,
                                     right: Constants.horizontalContentMargin)
        super.init(frame: frame)
        
        self.setup()
    }
    
    func setup() {
//        isMultipleTouchEnabled = false
        
        chartView.chartInsets = .init()
        chartView.backgroundColor = .clear
        cropFrameView.wantsLayer = true
        addSubview(chartView)
        lowerBoundTintView.isEventLess = true
        upperBoundTintView.isEventLess = true
        addSubview(lowerBoundTintView)
        addSubview(upperBoundTintView)
        addSubview(cropFrameView)
        
        cropFrameView.isEnabled = false
        
        cropFrameView.imageScaling = .scaleAxesIndependently
        
        cropFrameView.layer?.contentsGravity = .resize
        
        //cropFrameView.isUserInteractionEnabled = false
        chartView.userInteractionEnabled = false
        chartView.isEventLess = true
        lowerBoundTintView.userInteractionEnabled = false
        upperBoundTintView.userInteractionEnabled = false
        
        chartView.layer?.cornerRadius = 5
        upperBoundTintView.layer?.cornerRadius = 5
        lowerBoundTintView.layer?.cornerRadius = 5
        
        chartView.layer?.masksToBounds = true
        upperBoundTintView.layer?.masksToBounds = true
        lowerBoundTintView.layer?.masksToBounds = true
        
        selectionFrameView.isEventLess = true
        selectionFrameView.userInteractionEnabled = false
        selectionFrameView.isHidden = true
        addSubview(selectionFrameView)
        
        layoutViews()
    }
    
    private func applyStyle() {
        let usesGlass = self.chartStyle.usesGlass
        let radius: CGFloat = usesGlass ? Constants.glassCornerRadius : Constants.cornerRadius
        chartView.layer?.cornerRadius = radius
        upperBoundTintView.layer?.cornerRadius = radius
        lowerBoundTintView.layer?.cornerRadius = radius
        cropFrameView.isHidden = usesGlass
        selectionFrameView.isHidden = !usesGlass
        selectionFrameView.layer?.cornerRadius = radius
        selectionFrameView.layer?.borderWidth = usesGlass ? Constants.glassFrameWidth : 0
        if usesGlass {
            while glassHandles.count < 2 {
                let handle = View(frame: NSZeroRect)
                handle.isEventLess = true
                handle.userInteractionEnabled = false
                handle.layer?.cornerRadius = Constants.glassHandleWidth / 2
                handle.layer?.borderWidth = 0.5
                handle.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
                handle.layer?.shadowRadius = 1.5
                addSubview(handle)
                glassHandles.append(handle)
            }
        } else {
            for handle in glassHandles {
                handle.removeFromSuperview()
            }
            glassHandles.removeAll()
        }
        applyColors(animated: false)
        layoutViews()
    }
    
    private func applyColors(animated: Bool) {
        let theme = self.theme
        let usesGlass = self.chartStyle.usesGlass
        View.perform(animated: animated) {
            self.lowerBoundTintView.backgroundColor = usesGlass ? theme.rangeViewTintColor.withAlphaComponent(min(1, theme.rangeViewTintColor.alphaComponent * 1.6)) : theme.rangeViewTintColor
            self.upperBoundTintView.backgroundColor = self.lowerBoundTintView.backgroundColor
            self.selectionFrameView.layer?.borderColor = theme.rangeViewFrameColor.cgColor
        }
        self.applyHandleColors()
    }
    
    private func applyHandleColors() {
        let dark = self.theme.glassAppearance == .forceDark
        for handle in self.glassHandles {
            handle.backgroundColor = dark ? NSColor(white: 0, alpha: 0.34) : NSColor(white: 1, alpha: 0.94)
            handle.layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.2) : NSColor(white: 0, alpha: 0.1)).cgColor
            handle.layer?.shadowColor = NSColor.black.cgColor
            handle.layer?.shadowOpacity = dark ? 0.35 : 0.18
        }
    }
    
    
    public var rangeDidChangeClosure: ((ClosedRange<CGFloat>) -> Void)?
    public var touchedOutsideClosure: (() -> Void)?
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("not supported")
    }
    
    func setRangePaging(enabled: Bool, minimumSize: CGFloat) {
        isRangePagingEnabled = enabled
        minimumRangeDistance = minimumSize
    }
    
    func setRange(_ range: ClosedRange<CGFloat>, animated: Bool) {
        View.perform(animated: animated) {
            self.lowerBound = range.lowerBound
            self.upperBound = range.upperBound
            self.needsLayout = true
        }
    }
    
    override func layout() {
        super.layout()
        
        layoutViews()
    }
    
    override var isEnabled: Bool {
        get {
            return super.isEnabled
        }
        set {
            if newValue == false {
                selectedMarker = nil
            }
            super.isEnabled = newValue
        }
    }
    
    // MARK: - Touches
    
    override func mouseDown(with event: NSEvent) {
        
        super.mouseDown(with: event)
        
        guard isEnabled else { return }
        
        let point = self.convert(event.locationInWindow, from: nil)

        if abs(locationInView(for: upperBound) - point.x + Constants.markerSelectionRange / 2) < Constants.markerSelectionRange {
            selectedMarker = .upper
            selectedMarkerHorizontalOffet = point.x - locationInView(for: upperBound)
            isBoundCropHighlighted = true
        } else if abs(locationInView(for: lowerBound) - point.x - Constants.markerSelectionRange / 2) < Constants.markerSelectionRange {
            selectedMarker = .lower
            selectedMarkerHorizontalOffet = point.x - locationInView(for: lowerBound)
            isBoundCropHighlighted = true
        } else if point.x > locationInView(for: lowerBound) && point.x < locationInView(for: upperBound) {
            selectedMarker = .center
            selectedMarkerHorizontalOffet = point.x - locationInView(for: lowerBound)
            isBoundCropHighlighted = true
        } else {
            selectedMarker = nil
            return
        }

       // sendActions(for: .touchDown)
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        
        guard let selectedMarker = selectedMarker else { return }
        let point = self.convert(event.locationInWindow, from: nil)

        let horizontalPosition = point.x - selectedMarkerHorizontalOffet
        let fraction = fractionFor(offsetX: horizontalPosition)
        updateMarkerOffset(selectedMarker, fraction: fraction)

    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard isEnabled else { return }
        
        guard let selectedMarker = selectedMarker else {
            touchedOutsideClosure?()
            return
        }
        let point = self.convert(event.locationInWindow, from: nil)

        let horizontalPosition = point.x - selectedMarkerHorizontalOffet
        let fraction = fractionFor(offsetX: horizontalPosition)
        updateMarkerOffset(selectedMarker, fraction: fraction)
        
        self.selectedMarker = nil
        self.isBoundCropHighlighted = false

        rangeDidChangeClosure?(lowerBound...upperBound)

    }
}

private extension RangeChartView {
    var contentFrame: CGRect {
        return CGRect(x: layoutMargins.right,
                      y: layoutMargins.top,
                      width: (bounds.width - layoutMargins.right - layoutMargins.left),
                      height: bounds.height - layoutMargins.top - layoutMargins.bottom)
    }
    
    func locationInView(for fraction: CGFloat) -> CGFloat {
        return contentFrame.minX + contentFrame.width * fraction
    }
    
    func locationInView(for fraction: Double) -> CGFloat {
        return locationInView(for: CGFloat(fraction))
    }
    
    func fractionFor(offsetX: CGFloat) -> CGFloat {
        guard contentFrame.width > 0 else {
            return 0
        }
        
        return crop(0, CGFloat((offsetX - contentFrame.minX ) / contentFrame.width), 1)
    }
    
    private func updateMarkerOffset(_ marker: Marker, fraction: CGFloat, notifyDelegate: Bool = true) {
        let fractionToCount: CGFloat
        if isRangePagingEnabled {
            guard let minValue = stride(from: CGFloat(0.0), through: CGFloat(1.0), by: minimumRangeDistance).min(by: { abs($0 - fraction) < abs($1 - fraction) }) else { return }
            fractionToCount = minValue
        } else {
            fractionToCount = fraction
        }
        
        switch marker {
        case .lower:
            lowerBound = min(fractionToCount, upperBound - minimumRangeDistance)
        case .upper:
            upperBound = max(fractionToCount, lowerBound + minimumRangeDistance)
        case .center:
            let distance = upperBound - lowerBound
            lowerBound = max(0, min(fractionToCount, 1 - distance))
            upperBound = lowerBound + distance
        }
        if notifyDelegate {
            rangeDidChangeClosure?(lowerBound...upperBound)
        }
        self.layoutIfNeeded(animated: true)
    }
    
    // MARK: - Layout
    
    func layoutViews() {
        cropFrameView.frame = CGRect(x: locationInView(for: lowerBound),
                                     y: contentFrame.minY - Constants.cropIndocatorLineWidth,
                                     width: locationInView(for: upperBound) - locationInView(for: lowerBound),
                                     height: contentFrame.height + Constants.cropIndocatorLineWidth * 2)
        
        if chartView.frame != contentFrame {
            chartView.frame = contentFrame
        }
        
        lowerBoundTintView.frame = CGRect(x: contentFrame.minX,
                                          y: contentFrame.minY,
                                          width: max(0, locationInView(for: lowerBound) - contentFrame.minX + Constants.titntAreaWidth),
                                          height: contentFrame.height)
        
        upperBoundTintView.frame = CGRect(x: locationInView(for: upperBound) - Constants.titntAreaWidth,
                                          y: contentFrame.minY,
                                          width: max(0, contentFrame.maxX - locationInView(for: upperBound) + Constants.titntAreaWidth),
                                          height: contentFrame.height)
        
        if self.chartStyle.usesGlass {
            let lower = locationInView(for: lowerBound)
            let upper = locationInView(for: upperBound)
            selectionFrameView.frame = CGRect(x: lower, y: contentFrame.minY, width: max(0, upper - lower), height: contentFrame.height)
            let handleHeight = contentFrame.height - Constants.glassHandleInset * 2
            if glassHandles.count == 2 {
                glassHandles[0].frame = CGRect(x: lower + Constants.glassHandleInset, y: contentFrame.minY + Constants.glassHandleInset, width: Constants.glassHandleWidth, height: handleHeight)
                glassHandles[1].frame = CGRect(x: upper - Constants.glassHandleInset - Constants.glassHandleWidth, y: contentFrame.minY + Constants.glassHandleInset, width: Constants.glassHandleWidth, height: handleHeight)
                let shadowPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: Constants.glassHandleWidth, height: max(0, handleHeight)), cornerWidth: Constants.glassHandleWidth / 2, cornerHeight: Constants.glassHandleWidth / 2, transform: nil)
                for handle in glassHandles where handle.layer?.shadowPath?.boundingBox.height != max(0, handleHeight) {
                    handle.layer?.shadowPath = shadowPath
                }
            }
        }
    }
}

extension RangeChartView: ChartThemeContainer {
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        self.theme = theme
        self.applyHandleColors()
        let usesGlass = self.chartStyle.usesGlass
        let closure = {
            self.lowerBoundTintView.backgroundColor = usesGlass ? theme.rangeViewTintColor.withAlphaComponent(min(1, theme.rangeViewTintColor.alphaComponent * 1.6)) : theme.rangeViewTintColor
            self.upperBoundTintView.backgroundColor = self.lowerBoundTintView.backgroundColor
            self.selectionFrameView.layer?.borderColor = theme.rangeViewFrameColor.cgColor
        }
        
        let rangeCropImage = theme.rangeCropImage
        rangeCropImage?.resizingMode = .stretch
        rangeCropImage?.capInsets = NSEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        
        self.cropFrameView.setImage(rangeCropImage, animated: animated)

        //        self.chartView.apply(theme: theme, animated: animated)
        
        if animated {
            View.perform(animated: true, animations: closure)
        } else {
            closure()
        }
    }
}
