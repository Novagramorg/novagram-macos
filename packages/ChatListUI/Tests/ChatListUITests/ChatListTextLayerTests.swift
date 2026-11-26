import XCTest
import AppKit
import TGUIKit
@testable import ChatListUI

final class ChatListTextLayerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private struct Sample {
        let text: String
        let font: NSFont
        let color: NSColor
        let background: NSColor
        var width: CGFloat = .greatestFiniteMagnitude
    }

    private let samples: [Sample] = [
        Sample(text: "5:51 AM", font: .normal(.short), color: NSColor(white: 0.55, alpha: 1), background: .white),
        Sample(text: "Sat", font: .normal(.short), color: NSColor(white: 0.55, alpha: 1), background: .white),
        Sample(text: "Wed", font: .normal(.short), color: .white, background: NSColor(calibratedRed: 0.36, green: 0.47, blue: 0.86, alpha: 1)),
        Sample(text: "30.09.2026", font: .normal(.short), color: NSColor(white: 0.7, alpha: 1), background: NSColor(white: 0.12, alpha: 1)),
        Sample(text: "Обсуждение", font: .normal(.text), color: NSColor(white: 0.2, alpha: 1), background: .white),
        Sample(text: "Donald & Jack", font: .medium(.title), color: NSColor(white: 0.1, alpha: 1), background: .white),
        Sample(text: "Пресса.uz – Новости Узбекистана", font: .medium(.title), color: NSColor(white: 0.1, alpha: 1), background: .white, width: 150),
        Sample(text: "Leak Test Channel 6 Chat", font: .medium(.title), color: .white, background: NSColor(calibratedRed: 0.36, green: 0.47, blue: 0.86, alpha: 1)),
        Sample(text: "Telegram", font: .medium(.title), color: NSColor(white: 0.95, alpha: 1), background: NSColor(white: 0.12, alpha: 1)),
    ]

    private func layout(_ sample: Sample) -> TextViewLayout {
        let layout = TextViewLayout(.initialize(string: sample.text, color: sample.color, font: sample.font), maximumNumberOfLines: 1)
        layout.measure(width: sample.width)
        return layout
    }

    private func host(_ sample: Sample) -> View {
        let host = View(frame: NSMakeRect(0, 0, 240, 30))
        host.backgroundColor = sample.background
        return host
    }

    private let origin = NSMakePoint(31.5, 8)

    private func legacy(_ sample: Sample) -> View {
        let host = self.host(sample)
        let view = TextView()
        view.userInteractionEnabled = false
        view.isSelectable = false
        host.addSubview(view)
        view.update(layout(sample))
        view.setFrameOrigin(origin)
        return host
    }

    private func replacement(_ sample: Sample) -> (View, ChatListTextLayer) {
        let host = self.host(sample)
        let layer = ChatListTextLayer()
        host.layer?.addSublayer(layer)
        layer.update(layout(sample))
        layer.position = origin
        return (host, layer)
    }

    func testTextLayerRendersTheSamePixelsAsTextView() {
        for sample in samples {
            let old = ViewSnapshot.render(legacy(sample))
            let new = ViewSnapshot.render(replacement(sample).0)
            let empty = ViewSnapshot.render(host(sample))
            XCTAssertGreaterThan(old.differingPixels(from: empty), 20, sample.text)
            XCTAssertEqual(old.differingPixels(from: new), 0, sample.text)
        }
    }

    func testTextLayerKeepsTheTextViewFrame() {
        for sample in samples {
            let oldHost = legacy(sample)
            let new = replacement(sample)
            XCTAssertEqual(oldHost.subviews.first?.frame, new.1.frame, sample.text)
        }
    }

    func testTextLayerRendersAboveDrawnContent() {
        let layer = ChatListTextLayer()
        XCTAssertGreaterThan(layer.zPosition, 0)
        XCTAssertEqual(layer.anchorPoint, .zero)
    }

    func testAnimatedRemovalFadesLikeSubviewRemoval() {
        let host = View(frame: NSMakeRect(0, 0, 100, 30))
        let view = TextView()
        host.addSubview(view)
        view.update(layout(samples[0]))
        let layer = ChatListTextLayer()
        host.layer?.addSublayer(layer)
        layer.update(layout(samples[0]))
        performSubviewRemoval(view, animated: true)
        ChatListTextLayer.remove(layer, animated: true)
        XCTAssertEqual(Set(view.layer?.animationKeys() ?? []), Set(layer.animationKeys() ?? []))
        let legacyAnimation = view.layer?.animation(forKey: "opacity") as? CABasicAnimation
        let currentAnimation = layer.animation(forKey: "opacity") as? CABasicAnimation
        XCTAssertEqual(legacyAnimation?.duration, currentAnimation?.duration)
        XCTAssertEqual(legacyAnimation?.timingFunction, currentAnimation?.timingFunction)
        XCTAssertEqual(legacyAnimation?.toValue as? NSNumber, currentAnimation?.toValue as? NSNumber)
    }

    func testSameLayoutDoesNotRedraw() {
        let sample = samples[5]
        let first = layout(sample)
        let layer = ChatListTextLayer()
        layer.update(first)
        XCTAssertTrue(layer.hasPendingDisplay)
        layer.sublayers?.forEach { $0.displayIfNeeded() }
        XCTAssertFalse(layer.hasPendingDisplay)

        layer.update(first)
        XCTAssertFalse(layer.hasPendingDisplay)

        layer.update(layout(sample))
        XCTAssertTrue(layer.hasPendingDisplay)
    }
}
