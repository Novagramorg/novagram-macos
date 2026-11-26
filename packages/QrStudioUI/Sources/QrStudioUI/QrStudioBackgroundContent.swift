import Foundation
import Cocoa

protocol QrStudioBackgroundContent: NSView {
    var wantsFullFrameRate: Bool { get }

    func update(size: CGSize, revealCenter: CGPoint)
    func tick(time: Double, pan: QrStudioPan, drift: QrStudioDrift, tilt: SIMD2<Double>)
    func beginReveal(at time: Double)
    func setVisible(_ isVisible: Bool)
}
