import Cocoa
import TGUIKit

public final class PremiumGradientView : View {
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer = CAGradientLayer()

        self.gradient.startPoint = CGPoint(x: 0, y: 1)
        self.gradient.endPoint = CGPoint(x: 1, y: 0)

        gradient.colors = premiumGradient.compactMap { $0.cgColor }
    }


    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var gradient: CAGradientLayer {
        return self.layer! as! CAGradientLayer
    }
}
