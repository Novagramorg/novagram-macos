import Cocoa
import XCTest
import SwiftSignalKit
import Darwin
import ObjectiveC
@testable import TGUIKit

private final class LinkHoverTextView: TextView {
    override func mouseInside() -> Bool { true }
}

private enum ValueHoverLink {
    case peer(String)
}

final class TextViewLinkHoverTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func setUp() { TGUIKitTestBootstrap.install() }
    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
    }

    private func fixture(valueLink: Bool = false, decoration: String? = nil) -> (LinkHoverTextView, TextViewLayout) {
        let view = LinkHoverTextView()
        let text = NSMutableAttributedString(string: "First link Next link", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        text.addAttribute(.link, value: valueLink ? ValueHoverLink.peer("first") as Any : "first" as Any, range: NSRange(location: 0, length: 10))
        text.addAttribute(.link, value: valueLink ? ValueHoverLink.peer("next") as Any : "next" as Any, range: NSRange(location: 11, length: 9))
        if decoration == "spoiler" { text.addAttribute(TextInputAttributes.spoiler, value: true, range: NSRange(location: 11, length: 9)) }
        if decoration == "date" { text.addAttribute(TextInputAttributes.formattedDate, value: TextViewFormattedDateData(text: "Next link", date: 1000), range: NSRange(location: 11, length: 9)) }
        let layout = TextViewLayout(text)
        layout.measure(width: 240)
        view.update(layout)
        windows.append(TextViewReuseTests().window(view))
        return (view, layout)
    }

    private func hover(_ view: TextView, second: Bool = false, outside: Bool = false, at explicitPoint: NSPoint? = nil) {
        var point = NSPoint(x: 5, y: 5)
        if outside { point.x = view.bounds.width + 20 }
        if second, let layout = view.textLayout {
            for x in stride(from: CGFloat(1), to: view.bounds.width, by: 1) {
                if layout.link(at: NSPoint(x: x, y: 5))?.2.location == 11 {
                    point.x = x
                    break
                }
            }
        }
        if let explicitPoint { point = explicitPoint }
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 1, windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        view.checkCursor(event)
    }

    private func passDeadline() {
        let passed = expectation(description: "Hover deadline passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { passed.fulfill() }
        wait(for: [passed], timeout: 3)
    }

    func testActivePreviewSurvivesMovementOverSameLink() {
        for valueLink in [false, true] {
            let (view, layout) = fixture(valueLink: valueLink)
            let started = expectation(description: "Initial preview")
            var starts = 0, cancellations = 0
            layout.interactions.longHoverOnLink = { _, _ in
                starts += 1
                if starts == 1 { started.fulfill() }
                return ActionDisposable { cancellations += 1 }
            }
            hover(view)
            wait(for: [started], timeout: 3)
            for _ in 0..<20 { hover(view) }
            XCTAssertEqual(cancellations, 0)
            passDeadline()
            XCTAssertEqual(starts, 1)
            XCTAssertEqual(cancellations, 0)
            hover(view, outside: true)
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testLeavingAndReenteringLinkAllowsAnotherPreview() {
        let (view, layout) = fixture()
        let first = expectation(description: "First preview"), next = expectation(description: "Reentered preview")
        var starts = 0, cancellations = 0
        layout.interactions.longHoverOnLink = { _, _ in
            starts += 1
            if starts == 1 { first.fulfill() } else if starts == 2 { next.fulfill() }
            return ActionDisposable { cancellations += 1 }
        }
        hover(view)
        wait(for: [first], timeout: 3)
        hover(view, outside: true)
        XCTAssertEqual(cancellations, 1)
        hover(view)
        wait(for: [next], timeout: 3)
        XCTAssertEqual(starts, 2)
    }

    func testMovingToDifferentLinkCancelsPreviousPreview() {
        let (view, layout) = fixture()
        let first = expectation(description: "First link"), next = expectation(description: "Second link")
        var links: [String] = [], cancellations = 0
        layout.interactions.longHoverOnLink = { value, _ in
            links.append(value as! String)
            if links.count == 1 { first.fulfill() } else if links.count == 2 { next.fulfill() }
            return ActionDisposable { cancellations += 1 }
        }
        hover(view)
        wait(for: [first], timeout: 3)
        hover(view, second: true)
        XCTAssertEqual(cancellations, 1)
        wait(for: [next], timeout: 3)
        XCTAssertEqual(links, ["first", "next"])
    }

    func testReplacingLayoutCancelsPendingPreview() {
        var starts = 0
        for action in ["update", "set", "detach"] {
            let (view, layout) = fixture()
            layout.interactions.longHoverOnLink = { _, _ in starts += 1; return nil }
            hover(view)
            if action == "update" { view.update(TextViewReuseTests().layout()) }
            if action == "set" { view.set(layout: TextViewReuseTests().layout()) }
            if action == "detach" { view.removeFromSuperview() }
            withExtendedLifetime(layout) { passDeadline() }
        }
        XCTAssertEqual(starts, 0)
    }

    func testReplacingLayoutOrDetachingDisposesActivePreview() {
        for action in ["update", "set", "detach"] {
            let (view, layout) = fixture()
            let started = expectation(description: action)
            var cancellations = 0
            layout.interactions.longHoverOnLink = { _, _ in
                started.fulfill()
                return ActionDisposable { cancellations += 1 }
            }
            hover(view)
            wait(for: [started], timeout: 3)
            if action == "update" { view.update(TextViewReuseTests().layout()) }
            if action == "set" { view.set(layout: TextViewReuseTests().layout()) }
            if action == "detach" { view.removeFromSuperview() }
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testUpdatingSameLayoutPreservesActivePreview() {
        let (view, layout) = fixture()
        let started = expectation(description: "Preview")
        var cancellations = 0
        layout.interactions.longHoverOnLink = { _, _ in
            started.fulfill()
            return ActionDisposable { cancellations += 1 }
        }
        hover(view)
        wait(for: [started], timeout: 3)
        view.update(layout)
        view.set(layout: layout)
        XCTAssertEqual(cancellations, 0)
    }

    func testLayoutReplacementInsidePreviewFactoryDisposesReturnedWork() {
        let (view, layout) = fixture()
        let started = expectation(description: "Preview factory")
        let replacement = TextViewReuseTests().layout()
        var cancellations = 0
        layout.interactions.longHoverOnLink = { [weak view] _, _ in
            view?.update(replacement)
            started.fulfill()
            return ActionDisposable { cancellations += 1 }
        }
        hover(view)
        wait(for: [started], timeout: 3)
        XCTAssertTrue(view.textLayout === replacement)
        XCTAssertEqual(cancellations, 1)
    }

    func testCancellationCanScheduleNewPreviewWithoutLosingIt() {
        let (view, layout) = fixture()
        let first = expectation(description: "First preview"), next = expectation(description: "Replacement preview")
        let replacement = TextViewReuseTests().layout(link: true)
        replacement.interactions.longHoverOnLink = { _, _ in next.fulfill(); return nil }
        layout.interactions.longHoverOnLink = { [weak view, weak self] _, _ in
            first.fulfill()
            return ActionDisposable { [weak view, weak self] in
                guard let view else { return }
                view.update(replacement)
                self?.hover(view)
            }
        }
        hover(view)
        wait(for: [first], timeout: 3)
        hover(view, outside: true)
        wait(for: [next], timeout: 3)
        XCTAssertTrue(view.textLayout === replacement)
    }

    func testPreviewDisposalRebindingWinsOverOuterUpdate() {
        let (view, layout) = fixture()
        let started = expectation(description: "Preview")
        let replacement = TextViewReuseTests().layout("Newest layout")
        layout.interactions.longHoverOnLink = { [weak view] _, _ in
            started.fulfill()
            return ActionDisposable { [weak view] in view?.update(replacement) }
        }
        hover(view)
        wait(for: [started], timeout: 3)
        view.update(TextViewReuseTests().layout("Superseded layout"))
        XCTAssertTrue(view.textLayout === replacement)
        XCTAssertEqual(view.frame.size, replacement.layoutSize)
    }

    func testResetPreservesLayoutBoundDuringPreviewDisposal() {
        let (view, layout) = fixture()
        let started = expectation(description: "Preview")
        let replacement = TextViewReuseTests().layout("Newest layout")
        layout.interactions.longHoverOnLink = { [weak view] _, _ in
            started.fulfill()
            return ActionDisposable { [weak view] in view?.update(replacement) }
        }
        hover(view)
        wait(for: [started], timeout: 3)
        XCTAssertFalse(view.resetForContentChange())
        XCTAssertTrue(view.textLayout === replacement)
        XCTAssertEqual(view.frame.size, replacement.layoutSize)
    }

    func testFactoryCanScheduleDifferentLinkWithoutLosingNewRequest() {
        let (view, layout) = fixture()
        let started = expectation(description: "Replacement preview")
        var links: [String] = [], cancellations = 0
        layout.interactions.longHoverOnLink = { [weak self, weak view] value, _ in
            links.append(value as! String)
            if links.count == 1, let view { self?.hover(view, second: true) }
            if links.count == 2 { started.fulfill() }
            return ActionDisposable { cancellations += 1 }
        }
        hover(view)
        wait(for: [started], timeout: 4)
        XCTAssertEqual(links, ["first", "next"])
        XCTAssertEqual(cancellations, 1)
    }

    func testNilPreviewResultDoesNotRepeatUntilPointerLeaves() {
        let (view, layout) = fixture()
        let first = expectation(description: "First attempt"), next = expectation(description: "Reentered attempt")
        var starts = 0
        layout.interactions.longHoverOnLink = { _, _ in
            starts += 1
            if starts == 1 { first.fulfill() } else if starts == 2 { next.fulfill() }
            return nil
        }
        hover(view)
        wait(for: [first], timeout: 3)
        for _ in 0..<20 { hover(view) }
        passDeadline()
        XCTAssertEqual(starts, 1)
        hover(view, outside: true)
        hover(view)
        wait(for: [next], timeout: 3)
        XCTAssertEqual(starts, 2)
    }

    func testMovingToSpoilerOrFormattedDateCancelsPreview() throws {
        for decoration in ["spoiler", "date"] {
            let (view, layout) = fixture(decoration: decoration)
            let started = expectation(description: decoration)
            var starts = 0, cancellations = 0
            layout.interactions.longHoverOnLink = { _, _ in
                starts += 1
                if starts == 1 { started.fulfill() }
                return ActionDisposable { cancellations += 1 }
            }
            hover(view)
            wait(for: [started], timeout: 3)
            if decoration == "spoiler" {
                let rect = try XCTUnwrap(layout.spoilerRects().first?.0)
                hover(view, at: NSPoint(x: rect.midX, y: rect.midY))
            } else {
                hover(view, second: true)
            }
            XCTAssertEqual(cancellations, 1)
            hover(view, outside: true)
        }
    }

    func testChangingAttributedTextOnSameLayoutCancelsPreview() {
        for active in [false, true] {
            let (view, layout) = fixture()
            let started = active ? expectation(description: "Active preview") : nil
            var starts = 0, cancellations = 0
            layout.interactions.longHoverOnLink = { _, _ in
                starts += 1
                if starts == 1 { started?.fulfill() }
                return ActionDisposable { cancellations += 1 }
            }
            hover(view)
            if let started { wait(for: [started], timeout: 3) }
            layout.setAttributedString(TextViewReuseTests().layout().attributedString)
            layout.measure(width: 240)
            view.update(layout)
            if active {
                XCTAssertEqual(cancellations, 1)
            } else {
                passDeadline()
                XCTAssertEqual(starts, 0)
            }
        }
    }

    func testTimerRejectsTextReplacedWithoutViewUpdate() {
        let (view, layout) = fixture()
        var starts = 0
        layout.interactions.longHoverOnLink = { _, _ in starts += 1; return nil }
        hover(view)
        layout.setAttributedString(TextViewReuseTests().layout().attributedString)
        passDeadline()
        XCTAssertEqual(starts, 0)
    }

    func testMutatingOriginalAttributedStringRetargetsHover() throws {
        let (view, layout) = fixture()
        let source = try XCTUnwrap(layout.attributedString as? NSMutableAttributedString)
        let first = expectation(description: "First preview"), next = expectation(description: "Changed preview")
        var links: [String] = [], cancellations = 0
        layout.interactions.longHoverOnLink = { value, _ in
            links.append(value as! String)
            if links.count == 1 { first.fulfill() } else if links.count == 2 { next.fulfill() }
            return ActionDisposable { cancellations += 1 }
        }
        hover(view)
        wait(for: [first], timeout: 3)
        source.addAttribute(.link, value: "changed", range: NSRange(location: 0, length: 10))
        view.update(layout)
        XCTAssertEqual(cancellations, 1)
        hover(view)
        wait(for: [next], timeout: 3)
        XCTAssertEqual(links, ["first", "changed"])
    }

    func testTimerRejectsInPlaceTextMutation() throws {
        let (view, layout) = fixture()
        let source = try XCTUnwrap(layout.attributedString as? NSMutableAttributedString)
        var starts = 0
        layout.interactions.longHoverOnLink = { _, _ in starts += 1; return nil }
        hover(view)
        source.addAttribute(.link, value: "changed", range: NSRange(location: 0, length: 10))
        passDeadline()
        XCTAssertEqual(starts, 0)
    }

    func testDetachingBreaksPreviewSubscriptionRetentionOfView() {
        let source = ValuePipe<Int>()
        let started = expectation(description: "Preview subscription")
        var subscription: Disposable?
        defer { subscription?.dispose() }
        weak var released: TextView?
        var cancellations = 0
        autoreleasepool {
            let (view, layout) = fixture()
            released = view
            layout.interactions.longHoverOnLink = { _, owner in
                let disposable = (source.signal() |> afterDisposed { cancellations += 1 }).start(next: { _ in
                    owner.needsDisplay = true
                })
                subscription = disposable
                started.fulfill()
                return disposable
            }
            hover(view)
            wait(for: [started], timeout: 3)
            view.removeFromSuperview()
        }
        XCTAssertEqual(cancellations, 1)
        XCTAssertNil(released)
    }

    func testAllocationAndUpdateCosts() throws {
        guard let phase = ProcessInfo.processInfo.environment["TEXT_HOVER_BENCHMARK"] else { throw XCTSkip("Opt-in text hover allocation benchmark") }
        let view = TextView()
        let first = TextViewReuseTests().layout("First message"), next = TextViewReuseTests().layout("Next message")
        for _ in 0..<1000 { view.update(first); view.update(next) }
        var samples: [Double] = []
        for _ in 0..<9 {
            let start = CACurrentMediaTime()
            for _ in 0..<5000 { view.update(first); view.update(next) }
            samples.append((CACurrentMediaTime() - start) * 1e6 / 10000)
        }
        var replacements: [String: Int] = [:]
        for valueLink in [false, true] {
            let (hoverView, layout) = fixture(valueLink: valueLink)
            layout.interactions.longHoverOnLink = { _, _ in nil }
            func timer() -> SwiftSignalKit.Timer? {
                Mirror(reflecting: hoverView).superclassMirror?.children.first { $0.label == "longHoverTimer" }?.value as? SwiftSignalKit.Timer
            }
            hover(hoverView)
            var previous = try XCTUnwrap(timer())
            var count = 0
            for _ in 0..<100 {
                hover(hoverView)
                let current = try XCTUnwrap(timer())
                if current !== previous { count += 1 }
                previous = current
            }
            replacements[valueLink ? "value_link" : "string_link"] = count
        }
        var activeSamples: [String: [[Double]]] = [:]
        for length in [32, 1024, 8192] {
            let text = NSMutableAttributedString(string: "First link " + String(repeating: "x", count: length), attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
            text.addAttribute(.link, value: "first", range: NSRange(location: 0, length: 10))
            let layout = TextViewLayout(text, maximumNumberOfLines: 1)
            layout.measure(width: 240)
            let idle = LinkHoverTextView(), active = LinkHoverTextView()
            idle.update(layout)
            active.update(layout)
            windows.append(TextViewReuseTests().window(active))
            windows.append(TextViewReuseTests().window(idle))
            let started = expectation(description: "Active benchmark hover \(length)")
            layout.interactions.longHoverOnLink = { _, _ in started.fulfill(); return EmptyDisposable }
            hover(active)
            wait(for: [started], timeout: 3)
            for _ in 0..<1000 { idle.update(layout); active.update(layout) }
            var samples = [[Double](), [Double]()]
            let views = [idle, active]
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<1000 { views[variant].update(layout) }
                    samples[variant].append((CACurrentMediaTime() - start) * 1e6 / 1000)
                }
            }
            activeSamples[String(length + 11)] = samples
        }
        let report: [String: Any] = ["active_update_samples_idle_then_hovering": activeSamples, "pending_timer_replacements_per_100_moves": replacements, "unit": "microseconds_per_update", "samples": samples, "view_bytes": malloc_size(Unmanaged.passUnretained(view).toOpaque()), "instance_size": class_getInstanceSize(TextView.self)]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: "/tmp/text-hover-\(phase).json"))
    }
}
