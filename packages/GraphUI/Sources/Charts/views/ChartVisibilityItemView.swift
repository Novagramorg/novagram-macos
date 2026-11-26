import Cocoa
import TGUIKit
import GraphCore

class ChartVisibilityItemView: View {
    static let textFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    
    let checkButton: TextButton = TextButton()
    private var pillLayer: CALayer?
    private var sheenLayer: CAGradientLayer?
    
    var glassAppearance: LiquidGlassAppearance = .forceLight {
        didSet {
            if oldValue != self.glassAppearance {
                self.updateStyle(animated: false)
            }
        }
    }
    
    var chartStyle: ChartStyle = .classic {
        didSet {
            if oldValue != self.chartStyle {
                self.applyStyle()
            }
        }
    }
    
    required init(frame: CGRect) {
        super.init(frame: frame)
        
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    
    func setupView() {
        checkButton._thatFit = true
        checkButton.frame = bounds
        checkButton.set(font: ChartVisibilityItemView.textFont, for: .Normal)
        checkButton.layer?.cornerRadius = 6
        checkButton.layer?.masksToBounds = true
        checkButton.set(handler: { [weak self] _ in
            self?.didTapButton()
        }, for: .Click)
        addSubview(checkButton)
    }
    
    var tapClosure: (() -> Void)?
    var longTapClosure: (() -> Void)?
    
    private func applyStyle() {
        if self.chartStyle.usesGlass {
            if self.pillLayer == nil {
                let pillLayer = CALayer()
                pillLayer.actions = ["backgroundColor": NSNull(), "borderColor": NSNull(), "bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull()]
                let sheenLayer = CAGradientLayer()
                sheenLayer.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(), "opacity": NSNull()]
                sheenLayer.masksToBounds = true
                sheenLayer.startPoint = CGPoint(x: 0.5, y: 0)
                sheenLayer.endPoint = CGPoint(x: 0.5, y: 1)
                sheenLayer.locations = [0, 0.6]
                sheenLayer.colors = [NSColor(white: 1, alpha: 0.24).cgColor, NSColor(white: 1, alpha: 0).cgColor]
                self.layer?.insertSublayer(pillLayer, at: 0)
                self.layer?.insertSublayer(sheenLayer, above: pillLayer)
                self.pillLayer = pillLayer
                self.sheenLayer = sheenLayer
            }
        } else {
            self.pillLayer?.removeFromSuperlayer()
            self.sheenLayer?.removeFromSuperlayer()
            self.pillLayer = nil
            self.sheenLayer = nil
        }
        self.checkButton.layer?.cornerRadius = self.chartStyle.usesGlass ? self.bounds.height / 2 : 6
        self.needsLayout = true
        self.updateStyle(animated: false)
    }
    
    private func setPillColors(fill: NSColor, border: NSColor, sheen: Float, animated: Bool) {
        guard let pillLayer = self.pillLayer, let sheenLayer = self.sheenLayer else {
            return
        }
        if animated {
            for (keyPath, value) in [("backgroundColor", fill.cgColor), ("borderColor", border.cgColor)] {
                let animation = CABasicAnimation(keyPath: keyPath)
                animation.fromValue = pillLayer.presentation()?.value(forKeyPath: keyPath) ?? pillLayer.value(forKeyPath: keyPath)
                animation.toValue = value
                animation.duration = 0.2
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pillLayer.add(animation, forKey: keyPath)
            }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = sheenLayer.presentation()?.opacity ?? sheenLayer.opacity
            animation.toValue = sheen
            animation.duration = 0.2
            sheenLayer.add(animation, forKey: "opacity")
        }
        pillLayer.backgroundColor = fill.cgColor
        pillLayer.borderColor = border.cgColor
        pillLayer.borderWidth = 1
        sheenLayer.opacity = sheen
    }
    
    private func updateGlassStyle(animated: Bool) {
        guard let item = self.item else {
            return
        }
        let dark = self.glassAppearance == .forceDark
        if self.isChecked {
            self.setPillColors(fill: item.color, border: NSColor(white: 1, alpha: dark ? 0.22 : 0.38), sheen: 1, animated: animated)
        } else {
            self.setPillColors(fill: item.color.withAlphaComponent(0), border: item.color.withAlphaComponent(0.55), sheen: 0, animated: animated)
        }
        View.perform(animated: animated, animations: {
            self.checkButton.backgroundColor = .clear
            self.checkButton.layer?.borderColor = nil
            self.checkButton.layer?.borderWidth = 0
            if self.isChecked {
                self.checkButton.set(color: .white, for: .Normal)
                self.checkButton.set(text: "✓ " + item.title, for: .Normal)
            } else {
                self.checkButton.set(color: item.color, for: .Normal)
                self.checkButton.set(text: item.title, for: .Normal)
            }
        })
    }
    
    private func updateStyle(animated: Bool) {
        guard let item = item else {
            return
        }
        if self.chartStyle.usesGlass {
            self.updateGlassStyle(animated: animated)
            return
        }
        View.perform(animated: animated, animations: {
            if self.isChecked {
                self.checkButton.set(color: .white, for: .Normal)
                self.checkButton.backgroundColor = item.color
                self.checkButton.layer?.borderColor = nil
                self.checkButton.layer?.borderWidth = 0
                self.checkButton.set(text: "✓ " + item.title, for: .Normal)
            } else {
                self.checkButton.backgroundColor = .clear
                self.checkButton.layer?.borderColor = item.color.cgColor
                self.checkButton.layer?.borderWidth = 1
                self.checkButton.set(color: item.color, for: .Normal)
                self.checkButton.set(text: item.title, for: .Normal)
            }
            
        })
    }
    
    override func layout() {
        super.layout()
        
        checkButton.frame = bounds
        if let pillLayer = self.pillLayer, let sheenLayer = self.sheenLayer {
            pillLayer.frame = bounds
            pillLayer.cornerRadius = bounds.height / 2
            sheenLayer.frame = bounds.insetBy(dx: 1, dy: 1)
            sheenLayer.cornerRadius = (bounds.height - 2) / 2
            checkButton.layer?.cornerRadius = bounds.height / 2
        }
    }
    
    @objc private func didTapButton() {
        tapClosure?()
    }
    
    @objc private func didRecognizedLongPress(recognizer: NSGestureRecognizer) {
        if recognizer.state == .began {
            longTapClosure?()
        }
    }
    
    var item: ChartVisibilityItem? = nil {
        didSet {
            updateStyle(animated: false)
        }
    }
    
    private(set) var isChecked: Bool = true
    func setChecked(isChecked: Bool, animated: Bool) {
        self.isChecked = isChecked
        updateStyle(animated: true)
    }
}
