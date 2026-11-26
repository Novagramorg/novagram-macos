import XCTest
import AppKit
@testable import TGUIKit

private final class AnimationObserverTarget: NSObject {
    var firstCalls = 0
    var secondCalls = 0
    weak var lastObject: AnyObject?
    @objc func first(_ notification: Notification) {
        firstCalls += 1
        lastObject = notification.object as AnyObject?
    }
    @objc func second() { secondCalls += 1 }
}

private final class ObserverCountingRow: TableRowView {
    var animationCalls = 0
    var independentCalls = 0
    override func updateAnimatableContent() { animationCalls += 1 }
    @objc func independent(_ notification: Notification) { independentCalls += 1 }
}

private final class NotificationPayload {}

final class AnimationObserverLifecycleTests: XCTestCase {
    private var windows: [NSWindow] = []
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        super.tearDown()
    }
    private func root() -> NSView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        window.contentView = root
        windows.append(window)
        return root
    }
    private func scroll(in root: NSView) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 1000))
        root.addSubview(scroll)
        return scroll
    }
    private func post(_ name: Notification.Name, _ object: AnyObject) {
        NotificationCenter.default.post(name: name, object: object)
    }

    func testSelectorObserverDoesNotRetainDetachedSourceView() {
        let root = root(), target = AnimationObserverTarget()
        let old = LegacyAnimatableContentObserver(), new = AnimatableContentObserver()
        weak var oldView: NSView?
        weak var newView: NSView?
        autoreleasepool {
            let first = NSView(), second = NSView()
            root.addSubview(first); root.addSubview(second)
            old.update(for: first, target: target, selector: #selector(AnimationObserverTarget.first(_:)), options: [.ownFrame])
            new.update(for: second, target: target, selector: #selector(AnimationObserverTarget.first(_:)), options: [.ownFrame])
            first.removeFromSuperview(); second.removeFromSuperview()
            oldView = first; newView = second
        }
        XCTAssertNotNil(oldView)
        XCTAssertNil(newView)
        old.update(for: NSView(), target: target, selector: #selector(AnimationObserverTarget.first(_:)))
        XCTAssertNil(oldView)
    }

    func testSelectorObserverReleaseUnregistersWithoutRemovingOtherHandlers() {
        let root = root(), target = AnimationObserverTarget(), view = NSView()
        root.addSubview(view)
        NotificationCenter.default.addObserver(target, selector: #selector(AnimationObserverTarget.second), name: NSView.frameDidChangeNotification, object: view)
        defer { NotificationCenter.default.removeObserver(target) }
        var observer: AnimatableContentObserver? = AnimatableContentObserver()
        observer!.update(for: view, target: target, selector: #selector(AnimationObserverTarget.first(_:)), options: [.ownFrame])
        post(NSView.frameDidChangeNotification, view)
        XCTAssertEqual(target.firstCalls, 1)
        XCTAssertEqual(target.secondCalls, 1)
        observer = nil
        post(NSView.frameDidChangeNotification, view)
        XCTAssertEqual(target.firstCalls, 1)
        XCTAssertEqual(target.secondCalls, 2)
    }

    func testChangingOptionsSelectorAndViewReplacesRegistrations() {
        let root = root(), target = AnimationObserverTarget(), first = NSView(), second = NSView()
        root.addSubview(first); root.addSubview(second)
        let observer = AnimatableContentObserver()
        observer.update(for: first, target: target, selector: #selector(AnimationObserverTarget.first(_:)), options: [.ownFrame])
        post(NSView.frameDidChangeNotification, first)
        XCTAssertEqual(target.firstCalls, 1)
        XCTAssertTrue(target.lastObject === first)
        observer.update(for: first, target: target, selector: #selector(AnimationObserverTarget.first(_:)), options: [.ownBounds])
        post(NSView.frameDidChangeNotification, first)
        XCTAssertEqual(target.firstCalls, 1)
        post(NSView.boundsDidChangeNotification, first)
        XCTAssertEqual(target.firstCalls, 2)
        observer.update(for: first, target: target, selector: #selector(AnimationObserverTarget.second), options: [.ownBounds])
        post(NSView.boundsDidChangeNotification, first)
        XCTAssertEqual(target.firstCalls, 2)
        XCTAssertEqual(target.secondCalls, 1)
        observer.update(for: second, target: target, selector: #selector(AnimationObserverTarget.second), options: [.ownBounds])
        post(NSView.boundsDidChangeNotification, first)
        XCTAssertEqual(target.secondCalls, 1)
        post(NSView.boundsDidChangeNotification, second)
        XCTAssertEqual(target.secondCalls, 2)
    }

    func testRepeatedSelectorUpdatesDeliverExactlyOnceAndTargetCanDeallocate() {
        let root = root(), view = NSView(), observer = AnimatableContentObserver()
        root.addSubview(view)
        weak var released: AnimationObserverTarget?
        autoreleasepool {
            let target = AnimationObserverTarget()
            released = target
            for _ in 0..<1000 {
                observer.update(for: view, target: target, selector: #selector(AnimationObserverTarget.first(_:)), options: [.ownFrame])
            }
            post(NSView.frameDidChangeNotification, view)
            XCTAssertEqual(target.firstCalls, 1)
        }
        XCTAssertNil(released)
        post(NSView.frameDidChangeNotification, view)
    }

    func testSelectorRetargetsScrollContainersAndDetaches() {
        let root = root(), first = scroll(in: root), second = scroll(in: root)
        let view = NSView(), target = AnimationObserverTarget(), observer = AnimatableContentObserver()
        first.documentView!.addSubview(view)
        observer.update(for: view, target: target, selector: #selector(AnimationObserverTarget.first(_:)))
        post(NSView.boundsDidChangeNotification, first.contentView)
        XCTAssertEqual(target.firstCalls, 1)
        second.documentView!.addSubview(view)
        observer.update(for: view, target: target, selector: #selector(AnimationObserverTarget.first(_:)))
        post(NSView.boundsDidChangeNotification, first.contentView)
        XCTAssertEqual(target.firstCalls, 1)
        post(NSView.boundsDidChangeNotification, second.contentView)
        XCTAssertEqual(target.firstCalls, 2)
        view.removeFromSuperview()
        observer.update(for: view, target: target, selector: #selector(AnimationObserverTarget.first(_:)))
        post(NSView.boundsDidChangeNotification, second.contentView)
        XCTAssertEqual(target.firstCalls, 2)
    }

    func testTokenObserverStopsAfterDetachWhileBaselineKeepsCalling() {
        let root = root(), scroll = scroll(in: root), view = NSView()
        scroll.documentView!.addSubview(view)
        let old = LegacyAnimatableContentTokenObserver(), new = AnimatableContentTokenObserver()
        defer { old.removeObservers() }
        var oldCalls = 0, newCalls = 0
        old.update(for: view) { _ in oldCalls += 1 }
        new.update(for: view) { _ in newCalls += 1 }
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(oldCalls, 1); XCTAssertEqual(newCalls, 1)
        view.removeFromSuperview()
        old.update(for: view) { _ in oldCalls += 1 }
        new.update(for: view) { _ in newCalls += 1 }
        for _ in 0..<100 { post(NSView.boundsDidChangeNotification, scroll.contentView) }
        XCTAssertEqual(oldCalls, 101); XCTAssertEqual(newCalls, 1)
        scroll.documentView!.addSubview(view)
        new.update(for: view) { _ in newCalls += 1 }
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(newCalls, 2)
    }

    func testTokenHandlerChangesWithoutDuplicateRegistrations() {
        let root = root(), view = NSView(), observer = AnimatableContentTokenObserver()
        root.addSubview(view)
        var first = 0, second = 0
        observer.update(for: view) { _ in first += 1 }
        for _ in 0..<1000 { observer.update(for: view) { _ in second += 1 } }
        post(NSWindow.didBecomeKeyNotification, root.window!)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
        observer.removeObservers()
        post(NSWindow.didBecomeKeyNotification, root.window!)
        XCTAssertEqual(second, 1)
    }

    func testTokenObserverReleaseRemovesCallbacksAndCapturedPayload() {
        let root = root(), view = NSView()
        root.addSubview(view)
        var calls = 0
        weak var released: NotificationPayload?
        autoreleasepool {
            let payload = NotificationPayload()
            let observer = AnimatableContentTokenObserver()
            observer.update(for: view) { _ in withExtendedLifetime(payload) { calls += 1 } }
            released = payload
            post(NSWindow.didBecomeKeyNotification, root.window!)
            XCTAssertEqual(calls, 1)
            withExtendedLifetime(observer) {}
        }
        XCTAssertNil(released)
        post(NSWindow.didBecomeKeyNotification, root.window!)
        XCTAssertEqual(calls, 1)
    }

    func testTableRowIgnoresUnrelatedGeometryAndKeepsSubclassListeners() {
        let root = root(), row = ObserverCountingRow(frame: .zero), unrelated = NSView()
        NotificationCenter.default.addObserver(row, selector: #selector(ObserverCountingRow.independent(_:)), name: NSView.frameDidChangeNotification, object: row)
        root.addSubview(row); root.addSubview(unrelated)
        row.animationCalls = 0; row.independentCalls = 0
        for _ in 0..<1000 {
            post(NSView.frameDidChangeNotification, unrelated)
            post(NSView.boundsDidChangeNotification, unrelated)
        }
        XCTAssertEqual(row.animationCalls, 0)
        post(NSView.frameDidChangeNotification, row)
        XCTAssertEqual(row.animationCalls, 1)
        XCTAssertEqual(row.independentCalls, 1)
        post(NSWindow.didResizeNotification, root.window!)
        XCTAssertEqual(row.animationCalls, 2)
    }

    func testTableRowFollowsReparentingInsideOneWindow() {
        let root = root(), first = scroll(in: root), second = scroll(in: root)
        let row = ObserverCountingRow(frame: .zero)
        first.documentView!.addSubview(row)
        row.animationCalls = 0
        post(NSView.boundsDidChangeNotification, first.contentView)
        XCTAssertEqual(row.animationCalls, 1)
        second.documentView!.addSubview(row)
        row.animationCalls = 0
        post(NSView.boundsDidChangeNotification, first.contentView)
        XCTAssertEqual(row.animationCalls, 0)
        post(NSView.boundsDidChangeNotification, second.contentView)
        XCTAssertEqual(row.animationCalls, 1)
        row.removeFromSuperview()
        row.animationCalls = 0
        post(NSView.boundsDidChangeNotification, second.contentView)
        XCTAssertEqual(row.animationCalls, 0)
    }
}
