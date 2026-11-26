import XCTest
import AppKit
import TGUIKit
@testable import ChatUI

final class ChatRightTextLayerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private struct Sample {
        let text: String
        let font: NSFont
        let color: NSColor
    }

    private let samples: [Sample] = [
        Sample(text: "11:49 PM", font: .normal(.short), color: NSColor(white: 0.45, alpha: 1)),
        Sample(text: "edited", font: .italic(.small), color: .systemBlue),
        Sample(text: "76,9K", font: .normal(.small), color: .white),
        Sample(text: "Uzbek MDK, Акмал", font: .normal(.short), color: NSColor(white: 0.2, alpha: 0.8)),
        Sample(text: "5:46 AM", font: .normal(.short), color: NSColor(calibratedRed: 0.3, green: 0.55, blue: 0.2, alpha: 1)),
    ]

    private func layout(_ sample: Sample) -> TextViewLayout {
        let layout = TextViewLayout(.initialize(string: sample.text, color: sample.color, font: sample.font), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        return layout
    }

    private func host() -> View {
        let host = View(frame: NSMakeRect(0, 0, 140, 30))
        host.backgroundColor = NSColor(calibratedRed: 0.86, green: 0.95, blue: 0.8, alpha: 1)
        return host
    }

    private let origin = NSMakePoint(9.5, 7)

    private func legacy(_ sample: Sample) -> (View, TextView) {
        let host = self.host()
        let view = TextView(frame: NSRect(origin: origin, size: .zero))
        view.disableBackgroundDrawing = true
        view.userInteractionEnabled = false
        view.isSelectable = false
        host.addSubview(view)
        view.update(layout(sample))
        return (host, view)
    }

    private func replacement(_ sample: Sample) -> (View, ChatRightTextLayer) {
        let host = self.host()
        let layer = ChatRightView.makeTextLayer(NSRect(origin: origin, size: .zero))
        host.layer?.addSublayer(layer)
        layer.update(layout(sample))
        return (host, layer)
    }

    func testTextLayerRendersTheSamePixelsAsTextView() {
        for sample in samples {
            let old = legacy(sample)
            let new = replacement(sample)
            let oldPixels = ViewSnapshot.render(old.0)
            let newPixels = ViewSnapshot.render(new.0)
            XCTAssertGreaterThan(oldPixels.differingPixels(from: PixelBuffer(emptyLike: oldPixels, from: old.0)), 20, sample.text)
            XCTAssertEqual(oldPixels.differingPixels(from: newPixels), 0, sample.text)
        }
    }

    func testTextLayerKeepsTheTextViewFrame() {
        for sample in samples {
            let old = legacy(sample)
            let new = replacement(sample)
            XCTAssertEqual(old.1.frame, new.1.frame, sample.text)
            let target = NSMakeRect(20, 4, old.1.frame.width, old.1.frame.height)
            ContainedViewLayoutTransition.immediate.updateFrame(view: old.1, frame: target)
            ContainedViewLayoutTransition.immediate.updateFrame(layer: new.1, frame: target)
            new.1.updateDrawLayer()
            XCTAssertEqual(old.1.frame, new.1.frame, sample.text)
            XCTAssertEqual(ViewSnapshot.render(old.0).differingPixels(from: ViewSnapshot.render(new.0)), 0, sample.text)
        }
    }

    func testTextLayerRendersAboveViewSiblings() {
        let layer = ChatRightView.makeTextLayer(NSMakeRect(0, 0, 10, 10))
        XCTAssertGreaterThan(layer.zPosition, 0)
        XCTAssertEqual(layer.anchorPoint, .zero)
    }

    func testTextLayerRedrawsAtTheWindowScale() {
        let new = replacement(samples[0])
        new.1.updateScale(1)
        XCTAssertEqual(new.1.sublayers?.first?.contentsScale, 1)
        new.1.updateScale(2)
        XCTAssertEqual(new.1.sublayers?.first?.contentsScale, 2)
    }
}

private extension PixelBuffer {
    init(emptyLike other: PixelBuffer, from host: View) {
        let empty = View(frame: host.frame)
        empty.backgroundColor = host.backgroundColor
        self = ViewSnapshot.render(empty)
    }
}
