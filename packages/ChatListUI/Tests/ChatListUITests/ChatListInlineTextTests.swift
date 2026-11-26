import XCTest
import AppKit
import TGUIKit
import GeneralRows
@testable import ChatListUI

final class ChatListInlineTextTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private struct Sample {
        let text: String
        let lines: Int
        let width: CGFloat
        let font: NSFont
    }

    private let samples: [Sample] = [
        Sample(text: "Leak Test Channel 6 Chat", lines: 1, width: 200, font: .medium(.title)),
        Sample(text: "Leak Test Channel 6 Chat created the group \"Leak Test Channel 6 Chat\" and invited everyone", lines: 2, width: 200, font: .normal(.text)),
        Sample(text: "Пожар на «Карвон базаре» в Бухаре набирает обороты 🔥😳", lines: 2, width: 180, font: .normal(.text)),
        Sample(text: "You", lines: 1, width: 200, font: .normal(.text)),
    ]

    private func makeLayout(_ sample: Sample) -> TextViewLayout {
        let layout = TextViewLayout(.initialize(string: sample.text, color: NSColor.black, font: sample.font), maximumNumberOfLines: Int32(sample.lines))
        layout.measure(width: sample.width)
        return layout
    }

    private func legacy(_ sample: Sample) -> InteractiveTextView {
        let view = InteractiveTextView(frame: .zero)
        view.userInteractionEnabled = false
        view.set(text: makeLayout(sample), context: nil)
        return view
    }

    private func replacement(_ sample: Sample) -> ChatListInlineText {
        let text = ChatListInlineText()
        text.view.update(makeLayout(sample))
        return text
    }

    private func host(_ child: NSView) -> View {
        let host = View(frame: NSMakeRect(0, 0, 280, 60))
        host.backgroundColor = .white
        host.addSubview(child)
        child.setFrameOrigin(NSMakePoint(70, 9))
        return host
    }

    func testReplacementKeepsTheLegacyFrame() {
        for sample in samples {
            let old = legacy(sample)
            let new = replacement(sample)
            XCTAssertEqual(old.frame.size, new.view.frame.size, sample.text)
        }
    }

    func testReplacementRendersTheSamePixels() {
        for sample in samples {
            let old = ViewSnapshot.render(host(legacy(sample)))
            let new = ViewSnapshot.render(host(replacement(sample).view))
            XCTAssertGreaterThan(old.pixels(darkerThan: 128), 50, sample.text)
            XCTAssertEqual(old.differingPixels(from: new), 0, sample.text)
        }
    }

    func testReplacementIsOneViewInsteadOfTwo() {
        for sample in samples {
            XCTAssertEqual(viewTreeCount(legacy(sample)), 2)
            XCTAssertEqual(viewTreeCount(replacement(sample).view), 1)
        }
    }

    func testReplacementPassesClicksToTheRow() {
        let text = ChatListInlineText()
        XCTAssertFalse(text.view.userInteractionEnabled)
    }
}
