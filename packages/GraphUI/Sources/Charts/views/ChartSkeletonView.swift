import Cocoa
import TGUIKit
import GraphCore

private let shineWidth: CGFloat = 280
private let shineDuration: CFTimeInterval = 1.6
private let shineVirtualWidth: CGFloat = 2200

public final class ChartSkeletonView: View {
    public enum Shape: Equatable {
        case roundedRect(CGRect, cornerRadius: CGFloat)
        case stroke(CGPath, width: CGFloat)
    }

    private let fillLayer = CALayer()
    private let shineLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var shapes: [Shape] = []
    private var shineOriginX: CGFloat?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isEventLess = true
        let actions: [String: CAAction] = ["bounds": NSNull(), "position": NSNull(), "path": NSNull(), "backgroundColor": NSNull(), "colors": NSNull()]
        self.fillLayer.actions = actions
        self.shineLayer.actions = actions
        self.maskLayer.actions = actions
        self.shineLayer.startPoint = CGPoint(x: 0, y: 0.5)
        self.shineLayer.endPoint = CGPoint(x: 1, y: 0.5)
        self.shineLayer.locations = [0, 0.5, 1]
        self.fillLayer.addSublayer(self.shineLayer)
        self.fillLayer.mask = self.maskLayer
        self.layer?.addSublayer(self.fillLayer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(shapes: [Shape], baseColor: NSColor, highlightColor: NSColor) {
        self.fillLayer.backgroundColor = baseColor.cgColor
        self.shineLayer.colors = [highlightColor.withAlphaComponent(0).cgColor, highlightColor.cgColor, highlightColor.withAlphaComponent(0).cgColor]
        if self.shapes != shapes {
            self.shapes = shapes
            let path = CGMutablePath()
            for shape in shapes {
                switch shape {
                case let .roundedRect(rect, cornerRadius):
                    path.addPath(CGPath(roundedRect: rect, cornerWidth: min(cornerRadius, rect.width / 2), cornerHeight: min(cornerRadius, rect.height / 2), transform: nil))
                case let .stroke(strokePath, width):
                    path.addPath(strokePath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1))
                }
            }
            self.maskLayer.path = path
        }
    }

    public override func layout() {
        super.layout()
        self.fillLayer.frame = self.bounds
        self.maskLayer.frame = self.bounds
        self.shineLayer.frame = CGRect(x: -shineWidth, y: 0, width: shineWidth, height: self.bounds.height)
        self.updateShine()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.shineOriginX = nil
        self.updateShine()
    }

    private func updateShine() {
        guard self.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            self.shineLayer.removeAnimation(forKey: "shine")
            self.shineOriginX = nil
            return
        }
        let originX = self.convert(self.bounds, to: nil).minX
        if self.shineOriginX == originX, self.shineLayer.animation(forKey: "shine") != nil {
            return
        }
        self.shineOriginX = originX
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -shineWidth / 2 - originX
        animation.toValue = shineVirtualWidth - originX
        animation.duration = shineDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.beginTime = floor(CACurrentMediaTime() / shineDuration) * shineDuration
        animation.isRemovedOnCompletion = false
        self.shineLayer.add(animation, forKey: "shine")
    }

    public static func colors(isDark: Bool) -> (base: NSColor, highlight: NSColor) {
        if isDark {
            return (NSColor(white: 1, alpha: 0.07), NSColor(white: 1, alpha: 0.16))
        } else {
            return (NSColor(white: 0, alpha: 0.06), NSColor(white: 1, alpha: 0.75))
        }
    }

    private static let placeholderSeries = ["Followers", "Shares", "Reactions", "Views", "Others", "Muted"]
    
    public static func seriesFrames(width: CGFloat, seriesCount: Int) -> [CGRect] {
        let items = (0 ..< max(0, seriesCount)).map { ChartVisibilityItem(title: placeholderSeries[$0 % placeholderSeries.count], color: .gray) }
        return ChartVisibilityItem.generateItemsFrames(for: width, items: items)
    }
    
    public static func chartHeight(width: CGFloat, seriesCount: Int) -> CGFloat {
        return 308 + (self.seriesFrames(width: width, seriesCount: seriesCount).last?.maxY ?? 0)
    }
    
    public static func chartShapes(size: CGSize, seriesCount: Int) -> [Shape] {
        var shapes: [Shape] = []
        let left: CGFloat = 16
        let width = size.width - left * 2
        shapes.append(.roundedRect(CGRect(x: floor((size.width - 168) / 2), y: 19, width: 168, height: 12), cornerRadius: 6))
        let chartTop: CGFloat = 40
        let chartHeight: CGFloat = 175
        for line in 0 ..< 4 {
            let y = floor(chartTop + chartHeight * CGFloat(line + 1) / 4)
            shapes.append(.roundedRect(CGRect(x: left, y: y, width: width, height: 1), cornerRadius: 0))
            shapes.append(.roundedRect(CGRect(x: left, y: y - 15, width: 42, height: 9), cornerRadius: 4.5))
        }
        let wave = CGMutablePath()
        let steps = 48
        for step in 0 ... steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = left + width * t
            let y = chartTop + chartHeight * (0.58 - 0.22 * t - 0.09 * sin(t * .pi * 3.2) - 0.05 * sin(t * .pi * 9.1 + 1))
            if step == 0 {
                wave.move(to: CGPoint(x: x, y: y))
            } else {
                wave.addLine(to: CGPoint(x: x, y: y))
            }
        }
        shapes.append(.stroke(wave, width: 3))
        let labelCount = max(3, min(8, Int(width / 80)))
        for index in 0 ..< labelCount {
            let slot = width / CGFloat(labelCount)
            shapes.append(.roundedRect(CGRect(x: floor(left + slot * CGFloat(index) + (slot - 36) / 2), y: chartTop + chartHeight + 13, width: 36, height: 9), cornerRadius: 4.5))
        }
        shapes.append(.roundedRect(CGRect(x: left, y: 252, width: width, height: 42), cornerRadius: 9))
        for frame in self.seriesFrames(width: size.width, seriesCount: seriesCount) {
            shapes.append(.roundedRect(frame.offsetBy(dx: 0, dy: 308), cornerRadius: frame.height / 2))
        }
        return shapes
    }
}
