import AppKit

public final class RadialGradientView: View {

    private let gradientLayer = SimpleGradientLayer()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.addSublayer(gradientLayer)

        gradientLayer.type = .radial
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint   = CGPoint(x: 1.0, y: 1.0)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Gradient colors (NSColor array)
    public var colors: [NSColor] = [] {
        didSet {
            gradientLayer.colors = colors.map { $0.cgColor }
        }
    }

    public override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }
}
