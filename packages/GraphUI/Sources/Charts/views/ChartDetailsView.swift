import Cocoa
import TGUIKit
import GraphCore

private let cornerRadius: CGFloat = 5
private let verticalMargins: CGFloat = 8
private let labelHeight: CGFloat = 18
private let margin: CGFloat = 10
private let prefixLabelWidth: CGFloat = 35
private let minimumTextLabelWidth: CGFloat = 60
private let textFieldInset: CGFloat = 2
private let glassCornerRadius: CGFloat = 14
private let glassHorizontalMargin: CGFloat = 14
private let glassVerticalMargins: CGFloat = 10
private let titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
private let labelFont = NSFont.systemFont(ofSize: 12, weight: .regular)
private let valueFont = NSFont.systemFont(ofSize: 12, weight: .bold)
private let glassTitleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
private let glassValueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
private let totalRowKey = -1

private final class DetailsTextCache {
    private struct Key: Hashable {
        let text: String
        let font: NSFont
        let color: NSColor
    }
    
    private var entries: [Key: (TextNodeLayout, TextNode)] = [:]
    
    func layout(_ text: String, font: NSFont, color: NSColor) -> (TextNodeLayout, TextNode) {
        let key = Key(text: text, font: font, color: color)
        if let entry = self.entries[key] {
            return entry
        }
        if self.entries.count > 512 {
            self.entries.removeAll(keepingCapacity: true)
        }
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let entry = TextNode.layoutText(maybeNode: nil, attributed, nil, 1, .end, NSSize(width: 10000, height: labelHeight), nil, false, .left)
        self.entries[key] = entry
        return entry
    }
    
    func width(_ text: String, font: NSFont) -> CGFloat {
        return self.layout(text, font: font, color: .black).0.size.width
    }
}

private struct DetailsTextItem {
    enum Alignment {
        case left
        case right
    }
    let node: TextNode
    let size: NSSize
    let frame: CGRect
    let alignment: Alignment
}

private final class DetailsContentView: View {
    var items: [DetailsTextItem] = []
    var textBackgroundColor: NSColor = .clear
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let scale = self.window?.backingScaleFactor ?? System.backingScale
        for item in self.items {
            let width = min(item.size.width, item.frame.width - textFieldInset * 2)
            let x: CGFloat
            switch item.alignment {
            case .left:
                x = item.frame.minX + textFieldInset
            case .right:
                x = item.frame.maxX - textFieldInset - width
            }
            let y = item.frame.minY + floor((item.frame.height - item.size.height) / 2)
            item.node.draw(CGRect(x: x, y: y, width: width, height: item.size.height), in: ctx, backingScaleFactor: scale, backgroundColor: self.textBackgroundColor)
        }
    }
}

class ChartDetailsView: Control {
    override var alphaValue: CGFloat {
        didSet {
            self.isHidden = self.alphaValue == 0
        }
    }
    
    let arrowView = TransparentImageView()
    
    var chartStyle: ChartStyle = .classic {
        didSet {
            if oldValue != self.chartStyle {
                self.applyStyle()
            }
        }
    }
    
    private var viewModel: ChartDetailsViewModel?
    private var theme: ChartTheme = .defaultDayTheme
    private let textCache = DetailsTextCache()
    private let contentView = DetailsContentView()
    private var glassView: LiquidGlassView?
    private var titleMorph: ChartMorphingTextView?
    private var valueMorphs: [Int: ChartMorphingTextView] = [:]
    private var prefixMorphs: [Int: ChartMorphingTextView] = [:]
    private var contentSize = CGSize(width: 140, height: labelHeight + verticalMargins)
    
    required init(frame: CGRect) {
        super.init(frame: frame)
        
        self.layer?.cornerRadius = cornerRadius
        self.contentView.isEventLess = true
        self.addSubview(self.contentView)
        self.arrowView.image = NSImage.arrowRight
        self.arrowView.imageScaling = .scaleAxesIndependently
        self.arrowView.isHidden = true
        self.addSubview(self.arrowView)
        
        self.set(handler: { [weak self] _ in
            self?.viewModel?.tapAction?()
        }, for: .Click)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        self.contentView.frame = self.bounds
        self.glassView?.frame = self.bounds
    }
    
    private func applyStyle() {
        if self.chartStyle.usesGlass {
            if self.glassView == nil {
                let glassView = LiquidGlassView(frame: self.bounds, cornerRadius: glassCornerRadius, hasShadow: true, hasBorder: true)
                glassView.isEventLess = true
                self.addSubview(glassView, positioned: .below, relativeTo: self.contentView)
                self.glassView = glassView
            }
            self.layer?.cornerRadius = glassCornerRadius
            self.layer?.masksToBounds = false
        } else {
            self.glassView?.removeFromSuperview()
            self.glassView = nil
            self.layer?.cornerRadius = cornerRadius
            self.removeMorphViews()
        }
        self.rebuildLayout(animated: false)
        self.applyColors(animated: false)
        self.needsLayout = true
    }
    
    private func removeMorphViews() {
        self.titleMorph?.removeFromSuperview()
        self.titleMorph = nil
        self.valueMorphs.values.forEach { $0.removeFromSuperview() }
        self.valueMorphs.removeAll()
        self.prefixMorphs.values.forEach { $0.removeFromSuperview() }
        self.prefixMorphs.removeAll()
    }
    
    private func morphView(_ cache: inout [Int: ChartMorphingTextView], key: Int, alignment: ChartMorphingTextView.Alignment) -> ChartMorphingTextView {
        if let view = cache[key] {
            return view
        }
        let view = ChartMorphingTextView(frame: .zero)
        view.alignment = alignment
        view.clipsToRow = true
        self.addSubview(view, positioned: .above, relativeTo: self.contentView)
        cache[key] = view
        return view
    }
    
    private func applyColors(animated: Bool) {
        let theme = self.theme
        let usesGlass = self.chartStyle.usesGlass
        self.contentView.textBackgroundColor = usesGlass ? .clear : theme.chartDetailsViewColor
        self.glassView?.forceAppearance = theme.glassAppearance
        self.contentView.needsDisplay = true
        View.perform(animated: animated) {
            if #available(OSX 10.14, *) {
                self.arrowView.contentTintColor = theme.chartDetailsArrowColor
            }
            self.backgroundColor = usesGlass ? .clear : theme.chartDetailsViewColor
        }
    }
    
    private static func sameContent(_ lhs: ChartDetailsViewModel, _ rhs: ChartDetailsViewModel) -> Bool {
        func same(_ a: ChartDetailsViewModel.Value?, _ b: ChartDetailsViewModel.Value?) -> Bool {
            guard let a = a, let b = b else {
                return a == nil && b == nil
            }
            return a.visible == b.visible && a.value == b.value && a.title == b.title && a.prefix == b.prefix && a.color == b.color
        }
        guard lhs.title == rhs.title, lhs.showArrow == rhs.showArrow, lhs.showPrefixes == rhs.showPrefixes, lhs.isLoading == rhs.isLoading, lhs.values.count == rhs.values.count, same(lhs.totalValue, rhs.totalValue) else {
            return false
        }
        return zip(lhs.values, rhs.values).allSatisfy { same($0, $1) }
    }
    
    func setup(viewModel: ChartDetailsViewModel, animated: Bool) {
        if let current = self.viewModel, ChartDetailsView.sameContent(current, viewModel) {
            self.viewModel = viewModel
            return
        }
        let morphs = self.chartStyle.usesGlass && self.viewModel != nil && !self.isHidden && self.alphaValue > 0 && self.window != nil
        self.viewModel = viewModel
        self.rebuildLayout(animated: morphs)
    }
    
    private func rebuildLayout(animated: Bool = false) {
        defer {
            self.contentView.needsDisplay = true
        }
        guard let viewModel = self.viewModel else {
            self.contentView.items = []
            self.removeMorphViews()
            self.contentSize = CGSize(width: 140, height: labelHeight + verticalMargins)
            return
        }
        let usesGlass = self.chartStyle.usesGlass
        let textColor = usesGlass ? self.theme.chartTitleColor.withAlphaComponent(0.75) : self.theme.chartDetailsTextColor
        let titleColor = usesGlass ? self.theme.chartTitleColor : self.theme.chartDetailsTextColor
        let hasTitleRow = !viewModel.title.isEmpty || viewModel.showArrow
        
        func width(_ text: String, _ font: NSFont, glass glassFont: NSFont) -> CGFloat {
            if usesGlass {
                return ChartMorphingTextView.size(of: text, font: glassFont).width
            }
            return self.textCache.width(text, font: font)
        }
        
        var textLabelWidth = max(width(viewModel.title, titleFont, glass: glassTitleFont), minimumTextLabelWidth)
        var valueLabelWidth: CGFloat = 0
        for value in viewModel.values {
            textLabelWidth = max(textLabelWidth, self.textCache.width(value.title, font: labelFont))
            valueLabelWidth = max(valueLabelWidth, width(value.value, valueFont, glass: glassValueFont))
        }
        if let total = viewModel.totalValue {
            valueLabelWidth = max(valueLabelWidth, width(total.value, valueFont, glass: glassValueFont))
        }
        valueLabelWidth += textFieldInset * 2
        
        let horizontalMargin = usesGlass ? glassHorizontalMargin : margin
        let width = horizontalMargin * 2 + (viewModel.showPrefixes ? (prefixLabelWidth + margin) : 0) + textLabelWidth + valueLabelWidth
        var items: [DetailsTextItem] = []
        var y = usesGlass ? glassVerticalMargins : verticalMargins
        
        func add(_ text: String, font: NSFont, color: NSColor, frame: CGRect, alignment: DetailsTextItem.Alignment) {
            if text.isEmpty {
                return
            }
            let (layout, node) = self.textCache.layout(text, font: font, color: color)
            items.append(DetailsTextItem(node: node, size: layout.size, frame: frame, alignment: alignment))
        }
        
        var usedValues = Set<Int>()
        var usedPrefixes = Set<Int>()
        
        if hasTitleRow {
            let titleFrame = CGRect(x: horizontalMargin, y: y, width: width - horizontalMargin * 2, height: labelHeight)
            if usesGlass {
                let view: ChartMorphingTextView
                if let current = self.titleMorph {
                    view = current
                } else {
                    view = ChartMorphingTextView(frame: .zero)
                    view.clipsToRow = true
                    self.addSubview(view, positioned: .above, relativeTo: self.contentView)
                    self.titleMorph = view
                }
                view.frame = titleFrame.insetBy(dx: textFieldInset, dy: 0)
                view.update(text: viewModel.title, font: glassTitleFont, color: titleColor, animated: animated)
            } else {
                add(viewModel.title, font: titleFont, color: titleColor, frame: titleFrame, alignment: .left)
            }
            self.arrowView.frame = CGRect(x: width - 6 - horizontalMargin, y: usesGlass ? y + 4 : margin, width: 6, height: 10)
            y += labelHeight
        }
        if !hasTitleRow || !usesGlass {
            self.titleMorph?.removeFromSuperview()
            self.titleMorph = nil
        }
        self.arrowView.isHidden = !viewModel.showArrow
        
        func addRow(_ value: ChartDetailsViewModel.Value, key: Int, valueColor: NSColor) {
            if !value.visible {
                return
            }
            var x = horizontalMargin
            if viewModel.showPrefixes {
                let prefixFrame = CGRect(x: x, y: y, width: prefixLabelWidth, height: labelHeight)
                if usesGlass {
                    let view = self.morphView(&self.prefixMorphs, key: key, alignment: .right)
                    view.frame = prefixFrame.insetBy(dx: textFieldInset, dy: 0)
                    view.update(text: value.prefix ?? "", font: glassValueFont, color: textColor, animated: animated)
                    usedPrefixes.insert(key)
                } else {
                    add(value.prefix ?? "", font: valueFont, color: textColor, frame: prefixFrame, alignment: .right)
                }
                x += prefixLabelWidth + margin
            }
            add(value.title, font: labelFont, color: textColor, frame: CGRect(x: x, y: y, width: textLabelWidth, height: labelHeight), alignment: .left)
            let valueFrame = CGRect(x: width - valueLabelWidth - horizontalMargin, y: y, width: valueLabelWidth, height: labelHeight)
            if usesGlass {
                let view = self.morphView(&self.valueMorphs, key: key, alignment: .right)
                view.frame = valueFrame.insetBy(dx: textFieldInset, dy: 0)
                view.update(text: value.value, font: glassValueFont, color: valueColor, animated: animated)
                usedValues.insert(key)
            } else {
                add(value.value, font: valueFont, color: valueColor, frame: valueFrame, alignment: .right)
            }
            y += labelHeight
        }
        
        for (index, value) in viewModel.values.enumerated() {
            addRow(value, key: index, valueColor: value.color)
        }
        if let total = viewModel.totalValue {
            addRow(total, key: totalRowKey, valueColor: titleColor)
        }
        
        for key in Array(self.valueMorphs.keys) where !usedValues.contains(key) {
            self.valueMorphs.removeValue(forKey: key)?.removeFromSuperview()
        }
        for key in Array(self.prefixMorphs.keys) where !usedPrefixes.contains(key) {
            self.prefixMorphs.removeValue(forKey: key)?.removeFromSuperview()
        }
        
        self.contentView.items = items
        self.contentSize = CGSize(width: width, height: y + (usesGlass ? glassVerticalMargins : verticalMargins))
    }
    
    override var intrinsicContentSize: CGSize {
        return self.contentSize
    }
}

extension ChartDetailsView: ChartThemeContainer {
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        self.theme = theme
        self.rebuildLayout(animated: animated && self.chartStyle.usesGlass && !self.isHidden)
        self.applyColors(animated: animated)
    }
}

// MARK: UIStackView+removeAllArrangedSubviews
public extension NSStackView {
    func setLabelsCount(_ count: Int,
                        font: NSFont,
                        huggingPriority: NSLayoutConstraint.Priority,
                        textAlignment: NSTextAlignment = .right) {
        while arrangedSubviews.count > count {
            let subview = arrangedSubviews.last!
            removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        while arrangedSubviews.count < count {
            let label = TransparentTextField()
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            //label.allowsDefaultTighteningForTruncation = true
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            label.font = font
            label.alignment = textAlignment
            label.setContentHuggingPriority(huggingPriority, for: .horizontal)
            label.setContentHuggingPriority(huggingPriority, for: .vertical)
            label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 999), for: .horizontal)
            label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 999), for: .vertical)
            addArrangedSubview(label)
        }
    }
    
    func label(at index: Int) -> NSTextField {
        return arrangedSubviews[index] as! TransparentTextField
    }
    
    func removeAllArrangedSubviews() {
        for subview in arrangedSubviews {
            removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }
}

// MARK: UIStackView+addArrangedSubviews
public extension NSStackView {
    func addArrangedSubviews(_ views: [View]) {
        views.forEach({ addArrangedSubview($0) })
    }
}

// MARK: UIStackView+insertArrangedSubviews
public extension NSStackView {
    func insertArrangedSubviews(_ views: [View], at index: Int) {
        views.reversed().forEach({ insertArrangedSubview($0, at: index) })
    }
}
