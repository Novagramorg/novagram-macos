import XCTest
import AppKit
import TGUIKit
import Postbox
@testable import InlineMediaGrid

final class ChatMessageAccessoryViewTests: XCTestCase {
    struct Step {
        var text: String = "0:15"
        var status: MediaResourceStatus? = nil
        var isStreamable: Bool = false
        var isCompact: Bool = false
        var sound: Bool = false
        var isBuffering: Bool = false
        var isUnread: Bool = false
    }

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let soundImage: CGImage = {
        let context = CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 4, y: 4, width: 16, height: 16))
        return context.makeImage()!
    }()

    private func apply(_ step: Step, to view: ChatMessageAccessoryView, fetch: @escaping () -> Void = {}, cancelFetch: @escaping () -> Void = {}) {
        view.updateText(step.text, maxWidth: 200, status: step.status, isStreamable: step.isStreamable, isCompact: step.isCompact, soundOffOnImage: step.sound ? soundImage : nil, isBuffering: step.isBuffering, isUnread: step.isUnread, fetch: fetch, cancelFetch: cancelFetch)
        view.layoutSubtreeIfNeeded()
    }

    private func apply(_ step: Step, to view: LegacyChatMessageAccessoryView) {
        view.updateText(step.text, maxWidth: 200, status: step.status, isStreamable: step.isStreamable, isCompact: step.isCompact, soundOffOnImage: step.sound ? soundImage : nil, isBuffering: step.isBuffering, isUnread: step.isUnread)
        view.layoutSubtreeIfNeeded()
    }

    private func visibleTree(_ view: NSView) -> [String] {
        return view.subviews.filter { !$0.isHidden }.map { "\(type(of: $0)) \(NSStringFromRect($0.frame))" }
    }

    private func makeView(_ steps: [Step]) -> ChatMessageAccessoryView {
        let view = ChatMessageAccessoryView(frame: NSMakeRect(0, 0, 0, 0))
        for step in steps {
            apply(step, to: view)
        }
        return view
    }

    func testDownloadedVideoHoldsOnlyBackgroundAndText() {
        let view = makeView([Step(status: .Local, isStreamable: true)])
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView"])
        XCTAssertFalse(view.hasStremingControls)
    }

    func testNonStreamableVideoHoldsOnlyBackgroundAndText() {
        let view = makeView([Step()])
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView"])
    }

    func testRemoteVideoAddsOnlyTheDownloadButton() {
        let view = makeView([Step(text: "1:05, 12.3 MB", status: .Remote(progress: 0), isStreamable: true)])
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView", "ImageButton"])
        XCTAssertTrue(view.hasStremingControls)
    }

    func testFetchingAddsProgressBelowAHiddenDownloadButton() {
        let view = makeView([Step(text: "1:05, 12.3 MB", status: .Fetching(isActive: true, progress: 0.3), isStreamable: true)])
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView", "RadialProgressView", "ImageButton"])
        XCTAssertFalse(view.subviews[2].isHidden)
        XCTAssertTrue(view.subviews[3].isHidden)
        XCTAssertEqual(view.subviews[2].subviews.count, 1)
    }

    func testCompactFetchingAddsOnlyTheDownloadButton() {
        let view = makeView([Step(status: .Fetching(isActive: true, progress: 0.3), isStreamable: true, isCompact: true)])
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView", "ImageButton"])
        XCTAssertFalse(view.subviews[2].isHidden)
    }

    func testBufferingAndUnreadAreCreatedOnDemandAndKept() {
        let view = makeView([Step(isBuffering: true, isUnread: true)])
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView", "View", "ProgressIndicator"])
        apply(Step(), to: view)
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView", "View", "ProgressIndicator"])
        XCTAssertTrue(view.subviews[2].isHidden)
        XCTAssertTrue(view.subviews[3].isHidden)
    }

    func testOnDemandViewsKeepTheirOrderBelowTheSoundIcon() {
        let view = makeView([Step(sound: true), Step(status: .Remote(progress: 0), isStreamable: true, sound: true, isBuffering: true, isUnread: true), Step(status: .Fetching(isActive: true, progress: 0.5), isStreamable: true, sound: true)])
        XCTAssertEqual(viewClassNames(view.subviews), ["View", "TextView", "RadialProgressView", "ImageButton", "View", "ProgressIndicator", "ImageView"])
    }

    func testDownloadButtonAndProgressStillRouteFetching() {
        let view = ChatMessageAccessoryView(frame: .zero)
        var fetched = 0
        var cancelled = 0
        apply(Step(status: .Remote(progress: 0), isStreamable: true), to: view, fetch: { fetched += 1 }, cancelFetch: { cancelled += 1 })
        (view.subviews.last as? ImageButton)?.send(event: .Click)
        XCTAssertEqual(fetched, 1)
        apply(Step(status: .Fetching(isActive: true, progress: 0.3), isStreamable: true), to: view, fetch: { fetched += 1 }, cancelFetch: { cancelled += 1 })
        (view.subviews.first { $0 is RadialProgressView } as? RadialProgressView)?.fetchControls?.fetch()
        XCTAssertEqual(cancelled, 1)
    }

    func testMatchesTheEagerViewAcrossStates() {
        let steps: [Step] = [
            Step(),
            Step(text: "1:05, 12.3 MB", status: .Remote(progress: 0), isStreamable: true),
            Step(text: "1:05, 12.3 MB", status: .Fetching(isActive: true, progress: 0.3), isStreamable: true),
            Step(text: "1:05, 12.3 MB", status: .Paused(progress: 0.6), isStreamable: true),
            Step(status: .Fetching(isActive: true, progress: 0.4), isStreamable: true, isCompact: true),
            Step(status: .Remote(progress: 0), isStreamable: true, isCompact: true),
            Step(text: "1:05", status: .Local, isStreamable: true),
            Step(text: "0:07", isBuffering: true, isUnread: true),
            Step(text: "0:07", isUnread: true),
            Step(text: "0:42", sound: true, isBuffering: true),
            Step(text: "0:42", sound: true),
            Step(text: "1:05, 12.3 MB", status: .Remote(progress: 0), isStreamable: true),
        ]
        let view = ChatMessageAccessoryView(frame: NSMakeRect(0, 0, 0, 0))
        let legacy = LegacyChatMessageAccessoryView(frame: NSMakeRect(0, 0, 0, 0))
        for (index, step) in steps.enumerated() {
            apply(step, to: view)
            apply(step, to: legacy)
            assertMatches(view, legacy, "step \(index)")
            let freshView = ChatMessageAccessoryView(frame: NSMakeRect(0, 0, 0, 0))
            let freshLegacy = LegacyChatMessageAccessoryView(frame: NSMakeRect(0, 0, 0, 0))
            apply(step, to: freshView)
            apply(step, to: freshLegacy)
            assertMatches(freshView, freshLegacy, "fresh step \(index)")
        }
    }

    private func assertMatches(_ view: ChatMessageAccessoryView, _ legacy: LegacyChatMessageAccessoryView, _ message: String) {
        XCTAssertEqual(view.frame, legacy.frame, message)
        XCTAssertEqual(visibleTree(view), visibleTree(legacy), message)
        XCTAssertEqual(view.hasStremingControls, legacy.hasStremingControls, message)
        if !view.subviews.contains(where: { $0 is RadialProgressView && !$0.isHidden }) {
            let rendered = ViewSnapshot.render(view)
            let expected = ViewSnapshot.render(legacy)
            XCTAssertEqual(rendered.differingPixels(from: expected), 0, message)
        }
    }
}
