import Cocoa
import TGUIKit
import GraphCore

private enum Constants {
    static let itemHeight: CGFloat = 30
    static let itemSpacing: CGFloat = 8
    static let labelTextApproxInsets: CGFloat = 40
    static let insets = NSEdgeInsets(top: 0, left: 16, bottom: 16, right: 16)
}


class ChartVisibilityView: View {
    func playReveal(delay: CFTimeInterval) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        let now = CACurrentMediaTime()
        for (index, view) in self.selectionViews.enumerated() {
            guard let layer = view.layer else {
                continue
            }
            let begin = now + delay + Double(index) * 0.045
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.25
            fade.beginTime = begin
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "revealOpacity")
            let move = CASpringAnimation(keyPath: "position.y")
            move.fromValue = layer.position.y + (view.isFlipped ? -8 : 8)
            move.toValue = layer.position.y
            move.stiffness = 300
            move.damping = 26
            move.duration = move.settlingDuration
            move.beginTime = begin
            move.fillMode = .backwards
            layer.add(move, forKey: "revealPosition")
        }
    }
    
    var items: [ChartVisibilityItem] = [] {
        didSet {
            selectedItems = items.map { _ in true }
            while selectionViews.count > selectedItems.count {
                selectionViews.last?.removeFromSuperview()
                selectionViews.removeLast()
            }
            while selectionViews.count < selectedItems.count {
                let view = ChartVisibilityItemView(frame: bounds)
                view.glassAppearance = self.glassAppearance
                view.chartStyle = self.chartStyle
                addSubview(view)
                selectionViews.append(view)
            }
            
            assert(selectionViews.count == items.count)
            
            for (index, item) in items.enumerated() {
                let view = selectionViews[index]
                view.item = item
                view.tapClosure = { [weak self] in
                    guard let self = self else { return }
                    let selected = self.selectedItems.filter { $0 }
                    if selected.count == 1, self.selectedItems[index] {
                        self.selectionViews[index].shake()
                    } else {
                        self.setItemSelected(!self.selectedItems[index], at: index, animated: true)
                        self.notifyItemSelection()
                    }
                }
                
                view.longTapClosure = { [weak self] in
                    guard let self = self else { return }
                    let hasSelectedItem = self.selectedItems.enumerated().contains(where: { $0.element && $0.offset != index })
                    if hasSelectedItem {
                        for (itemIndex, _) in self.items.enumerated() {
                            self.setItemSelected(itemIndex == index, at: itemIndex, animated: true)
                        }
                    } else {
                        for (itemIndex, _) in self.items.enumerated() {
                            self.setItemSelected(true, at: itemIndex, animated: true)
                        }
                    }
                    self.notifyItemSelection()
                }
            }
        }
    }
    
    private var glassAppearance: LiquidGlassAppearance = .forceLight
    
    var chartStyle: ChartStyle = .classic {
        didSet {
            for view in self.selectionViews {
                view.chartStyle = self.chartStyle
            }
        }
    }
    
    private(set) var selectedItems: [Bool] = []
    var isExpanded: Bool = true {
        didSet {
            invalidateIntrinsicContentSize()
           // setNeedsUpdateConstraints()
        }
    }
    
    private var selectionViews: [ChartVisibilityItemView] = []
    
    var selectionCallbackClosure: (([Bool]) -> Void)?
    
    func setItemSelected(_ selected: Bool, at index: Int, animated: Bool) {
        self.selectedItems[index] = selected
        self.selectionViews[index].setChecked(isChecked: selected, animated: animated)
    }
    
    func setItemsSelection(_ selection: [Bool]) {
        assert(selection.count == items.count)
        self.selectedItems = selection
        for (index, selected) in self.selectedItems.enumerated() {
            selectionViews[index].setChecked(isChecked: selected, animated: false)
        }
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
    }
    
    private func notifyItemSelection() {
        selectionCallbackClosure?(selectedItems)
    }
    
    override func layout() {
        super.layout()
        
        updateFrames()
    }
    
    override var alphaValue: CGFloat {
        didSet {
            if self.alphaValue == 0 {
                var bp:Int = 0
                bp += 1
            }
        }
    }
    
    private func updateFrames() {
        let frames = ChartVisibilityItem.generateItemsFrames(for: frame.width, items: self.items)
        for (index, frame) in frames.enumerated() {
            selectionViews[index].frame = frame
        }
    }
    
}

extension ChartVisibilityView: ChartThemeContainer {
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        self.glassAppearance = theme.glassAppearance
        for view in self.selectionViews {
            view.glassAppearance = theme.glassAppearance
        }
        View.perform(animated: animated) {
            self.backgroundColor = theme.chartBackgroundColor
          //  self.tintColor = theme.descriptionActionColor
        }
    }
}
