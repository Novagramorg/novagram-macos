import AppKit
import XCTest
@testable import TGUIKit

final class ObserverLookupView: NSView {
    var lookups = 0
    override var enclosingScrollView: NSScrollView? {
        lookups += 1
        return super.enclosingScrollView
    }
}

final class ObserverWorkTarget: NSObject {
    var calls = 0
    var handler: ((Notification) -> Void)?
    @objc func receive(_ notification: Notification) {
        calls += 1
        handler?(notification)
    }
}

final class AnimationObserverWorkTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func setUp() { TGUIKitTestBootstrap.install() }

    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        super.tearDown()
    }

    func attach(_ view: NSView, depth: Int = 8) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1000))
        scroll.documentView = document
        window.contentView = scroll
        var parent = document
        for _ in 0..<depth {
            let child = NSView(frame: parent.bounds)
            parent.addSubview(child)
            parent = child
        }
        parent.addSubview(view)
        windows.append(window)
        return window
    }

    func storedReceiver(_ observer: AnyObject) -> AnyObject? {
        guard let value = Mirror(reflecting: observer).children.first(where: { $0.label?.contains("notificationTarget") == true })?.value else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.map { $0.value as AnyObject }
        }
        return value as AnyObject
    }

    func testUnusedAndDetachedObserverDoNotAllocateReceiver() {
        let observer = AnimatableContentObserver(), view = NSView(), target = ObserverWorkTarget()
        XCTAssertNil(storedReceiver(observer))
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        XCTAssertNil(storedReceiver(observer))
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)), contentView: nil, documentView: nil, options: [.ownFrame])
        XCTAssertNil(storedReceiver(observer))
    }

    func testReceiverIsCreatedOnceAndRetainedForReuse() throws {
        let observer = AnimatableContentObserver(), view = NSView(), target = ObserverWorkTarget()
        let window = attach(view), parent = view.superview!
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        let receiver = try XCTUnwrap(storedReceiver(observer))
        view.removeFromSuperview()
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        XCTAssertTrue(storedReceiver(observer) === receiver)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(target.calls, 0)
        parent.addSubview(view)
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        XCTAssertTrue(storedReceiver(observer) === receiver)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(target.calls, 1)
    }

    func testSelectorUpdateLooksUpScrollContainerOnce() {
        let view = ObserverLookupView(), target = ObserverWorkTarget(), observer = AnimatableContentObserver()
        _ = attach(view)
        view.lookups = 0
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        XCTAssertEqual(view.lookups, 1)
        view.lookups = 0
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        XCTAssertEqual(view.lookups, 1)
    }

    func testDetachedSelectorUpdateDoesNotWalkScrollHierarchy() {
        let view = ObserverLookupView(), target = ObserverWorkTarget(), observer = AnimatableContentObserver()
        let parent = NSView()
        parent.addSubview(view)
        view.lookups = 0
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        XCTAssertEqual(view.lookups, 0)
    }

    func testTokenUpdateLooksUpScrollContainerOnce() {
        let view = ObserverLookupView(), observer = AnimatableContentTokenObserver()
        _ = attach(view)
        view.lookups = 0
        observer.update(for: view) { _ in }
        XCTAssertEqual(view.lookups, 1)
        view.lookups = 0
        observer.update(for: view) { _ in }
        XCTAssertEqual(view.lookups, 1)
    }

    func testExplicitContainersAvoidHierarchyLookup() {
        let view = ObserverLookupView(), target = ObserverWorkTarget(), observer = AnimatableContentObserver()
        let window = attach(view)
        let scroll = window.contentView as! NSScrollView
        view.lookups = 0
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)), contentView: scroll.contentView, documentView: scroll.documentView, options: [.contentBounds])
        XCTAssertEqual(view.lookups, 0)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        XCTAssertEqual(target.calls, 1)
    }

    func testReleasingObserverDuringDeliveryStopsNestedDelivery() {
        let view = NSView(), target = ObserverWorkTarget()
        let window = attach(view)
        var observer: AnimatableContentObserver? = AnimatableContentObserver()
        weak var released = observer
        observer?.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        target.handler = { _ in
            if target.calls == 1 {
                observer = nil
                XCTAssertNil(released)
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            }
        }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertNil(released)
        XCTAssertEqual(target.calls, 1)
        target.handler = nil
    }

    func testDetachDuringDeliveryStopsNestedDeliveryAndReattaches() {
        let view = NSView(), target = ObserverWorkTarget(), observer = AnimatableContentObserver()
        let window = attach(view)
        let parent = view.superview!
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        target.handler = { _ in
            if target.calls == 1 {
                view.removeFromSuperview()
                observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            }
        }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(target.calls, 1)
        target.handler = nil
        parent.addSubview(view)
        observer.update(for: view, target: target, selector: #selector(ObserverWorkTarget.receive(_:)))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(target.calls, 2)
    }
}
