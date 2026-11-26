import XCTest
import QuartzCore
import StarsUI
import PremiumStatusUI

final class StarsEmitterPauseTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func emitter(_ layer: CALayer) -> CAEmitterLayer? {
        return layer.sublayers?.compactMap { $0 as? CAEmitterLayer }.first
    }

    func testStarReactionEmitterStopsWhenNotPlaying() {
        let layer = StarsButtonEffectLayer()
        layer.update(size: CGSize(width: 40, height: 30))
        XCTAssertEqual(layer.emitterLayer.birthRate, 1)
        layer.isPlaying = false
        XCTAssertEqual(layer.emitterLayer.birthRate, 0)
        layer.isPlaying = true
        XCTAssertEqual(layer.emitterLayer.birthRate, 1)
    }

    func testGiftStatusEmitterStopsWhenNotPlaying() {
        let layer = StarsEffectLayer()
        layer.update(color: .systemYellow, size: CGSize(width: 25, height: 25))
        XCTAssertEqual(self.emitter(layer)?.birthRate, 1)
        layer.isPlaying = false
        XCTAssertEqual(self.emitter(layer)?.birthRate, 0)
        layer.isPlaying = true
        XCTAssertEqual(self.emitter(layer)?.birthRate, 1)
    }
}
