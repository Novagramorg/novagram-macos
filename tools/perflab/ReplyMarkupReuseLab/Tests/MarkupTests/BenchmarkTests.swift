import Cocoa
import XCTest
import TGUIKit

final class BenchmarkTests: XCTestCase {
    func testRedrawCost() throws {
        guard ProcessInfo.processInfo.environment["MARKUP_BENCHMARK"] != nil else { throw XCTSkip("Opt-in native reply markup benchmark") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["MARKUP_REVERSE"] != nil
        GeneralRowsHooks.shared.makeInlineTextRenderer = { let renderer = RendererFixture(); renderer.recordsEvents = false; return renderer }
        let interactions = ReplyMarkupInteractions()
        let theme = TelegramPresentationTheme()
        var samples: [String: [Double]] = [:]
        for count in [1, 6, 24] {
            for embedded in [false, true] {
                let rows = [ReplyMarkupRow(buttons: (0..<count).map { .init(title: "Button \($0)", action: .copyText, embedded: embedded) })]
                let oldHost = View()
                let newHost = ReplyMarkupContainerView()
                let frame = NSRect(x: 0, y: 0, width: CGFloat(count * 100), height: 40)
                let oldWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                let newWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                oldWindow.isReleasedWhenClosed = false
                newWindow.isReleasedWhenClosed = false
                oldHost.frame = frame
                newHost.frame = frame
                oldWindow.contentView!.addSubview(oldHost)
                newWindow.contentView!.addSubview(newHost)
                let old = ReferenceReplyMarkupNode(rows, [], interactions, theme, oldHost)
                let new = CandidateReplyMarkupNode(rows, [], interactions, theme, newHost)
                old.measureSize(CGFloat(count * 100))
                new.measureSize(CGFloat(count * 100))
                old.redraw(); old.layout(); new.redraw(); new.layout()
                for batch in -1..<9 {
                    for native in ((batch % 2 == 0) != reverse ? [true, false] : [false, true]) {
                        autoreleasepool {
                            let start = CACurrentMediaTime()
                            for _ in 0..<200 {
                                if native { old.redraw(); old.layout(); oldHost.layoutSubtreeIfNeeded() } else { new.redraw(); new.layout(); newHost.layoutSubtreeIfNeeded() }
                            }
                            CATransaction.flush()
                            let elapsed = (CACurrentMediaTime() - start) * 1_000_000 / 200
                            if batch >= 0 { samples["buttons-\(count)-embedded-\(embedded)-\(native ? "before" : "after")", default: []].append(elapsed) }
                        }
                    }
                }
                XCTAssertEqual(oldHost.subviews.count, count)
                XCTAssertEqual(newHost.subviews.count, count)
                oldWindow.close()
                newWindow.close()
            }
        }
        let payload: [String: Any] = ["microseconds_per_redraw_and_layout": samples, "reverse": reverse, "scope": "Full production node and InteractiveTextView; premeasured layouts, attached AppKit views with completed layout, inline decoder/account/theme stand-ins."]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: URL(fileURLWithPath: "/tmp/reply-markup-timing\(reverse ? "-reverse" : "").json"))
    }
}
