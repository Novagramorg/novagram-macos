import Cocoa
import XCTest
import SwiftSignalKit
import ObjectiveC
import Darwin
@testable import TGUIKit

private final class DeferredMenuTextView: TextView {
    override func mouseInside() -> Bool { true }
}

private final class DeferredMenuRowItem: TableRowItem {
    var starts = 0
    var cancellations = 0

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        Signal { [weak self] _ in
            self?.starts += 1
            return ActionDisposable { [weak self] in self?.cancellations += 1 }
        }
    }
}

private final class DeferredPressureRow: TableRowView {
    var clicks = 0
    override func forceClick(in location: NSPoint) { clicks += 1 }
}

final class DeferredInteractionTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func holder(_ object: Any, _ name: String) -> Disposable? {
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            if let value = current.children.first(where: { $0.label == name })?.value {
                return value as? Disposable
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    private func event() -> NSEvent {
        NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
    }

    func testIdleTextAndResetDoNotAllocateMenuState() {
        let view = TextView()
        XCTAssertNil(holder(view, "menuDisposable"))
        view.update(TextViewReuseTests().layout())
        XCTAssertTrue(view.resetForContentChange())
        XCTAssertNil(holder(view, "menuDisposable"))
    }

    func testIdleRowAndMissingItemMenuDoNotAllocateInteractionState() {
        let view = TableRowView(frame: .zero)
        view.showContextMenu(event())
        XCTAssertNil(holder(view, "menuDisposable"))
        XCTAssertNil(holder(view, "longDisposable"))
    }

    func testTextMenuReplacementResetAndDeinitCancelPendingRequests() throws {
        for customMenu in [false, true] {
            var starts = 0, cancellations = 0
            weak var released: TextView?
            autoreleasepool {
                let view = DeferredMenuTextView()
                released = view
                let layout = TextViewReuseTests().layout(link: true)
                layout.alwaysStaticItems = false
                if customMenu {
                    layout.interactions.menuItems = { _ in
                        Signal { _ in
                            starts += 1
                            return ActionDisposable { cancellations += 1 }
                        }
                    }
                } else {
                    layout.interactions.topWindow = {
                        Signal { _ in
                            starts += 1
                            return ActionDisposable { cancellations += 1 }
                        }
                    }
                }
                view.update(layout)
                view.rightMouseDown(with: event())
                let first = holder(view, "menuDisposable")
                XCTAssertNotNil(first)
                XCTAssertEqual(starts, 1)
                XCTAssertEqual(cancellations, 0)
                view.rightMouseDown(with: event())
                XCTAssertTrue(holder(view, "menuDisposable") === first)
                XCTAssertEqual(starts, 2)
                XCTAssertEqual(cancellations, 1)
                XCTAssertTrue(view.resetForContentChange())
                XCTAssertEqual(cancellations, 2)
                view.update(layout)
                view.rightMouseDown(with: event())
                XCTAssertTrue(holder(view, "menuDisposable") === first)
                XCTAssertEqual(starts, 3)
            }
            XCTAssertNil(released)
            XCTAssertEqual(cancellations, 3)
        }
    }

    func testRowMenuReplacementAndDeinitCancelPendingRequests() {
        let item = DeferredMenuRowItem(.zero)
        weak var released: TableRowView?
        autoreleasepool {
            let view = TableRowView(frame: .zero)
            released = view
            view.set(item: item)
            XCTAssertNil(holder(view, "menuDisposable"))
            view.showContextMenu(event())
            let first = holder(view, "menuDisposable")
            XCTAssertNotNil(first)
            XCTAssertEqual(item.starts, 1)
            XCTAssertEqual(item.cancellations, 0)
            view.showContextMenu(event())
            XCTAssertTrue(holder(view, "menuDisposable") === first)
            XCTAssertEqual(item.starts, 2)
            XCTAssertEqual(item.cancellations, 1)
        }
        XCTAssertNil(released)
        XCTAssertEqual(item.cancellations, 2)
    }

    func testPressureAllocatesOnDemandAndCancelsOnReleaseOrDeepClick() throws {
        let method = try XCTUnwrap(class_getInstanceMethod(NSEvent.self, #selector(getter: NSEvent.stage)))
        var stage = 0
        let replacement = imp_implementationWithBlock({ (_: AnyObject) -> Int in stage } as @convention(block) (AnyObject) -> Int)
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        let view = DeferredPressureRow(frame: .zero)
        view.pressureChange(with: event())
        XCTAssertNil(holder(view, "longDisposable"))
        stage = 1
        view.pressureChange(with: event())
        let first = try XCTUnwrap(holder(view, "longDisposable"))
        func hasPending() -> Bool {
            let value = Mirror(reflecting: first).children.first { $0.label == "disposable" }!.value
            return Mirror(reflecting: value).children.count != 0
        }
        XCTAssertTrue(hasPending())
        stage = 0
        view.pressureChange(with: event())
        XCTAssertFalse(hasPending())
        stage = 1
        view.pressureChange(with: event())
        XCTAssertTrue(holder(view, "longDisposable") === first)
        XCTAssertTrue(hasPending())
        stage = 2
        view.pressureChange(with: event())
        XCTAssertFalse(hasPending())
        XCTAssertEqual(view.clicks, 1)
        XCTAssertNil(holder(view, "menuDisposable"))
    }

    func testConstructionBenchmark() throws {
        guard let variant = ProcessInfo.processInfo.environment["DEFERRED_INTERACTION_BENCHMARK"] else { throw XCTSkip("Opt-in deferred interaction benchmark") }
        var samples: [String: [Double]] = [:]
        let cases: [(String, () -> NSView)] = [("text", { TextView() }), ("row", { TableRowView(frame: .zero) })]
        for (_, make) in cases { for _ in 0..<100 { autoreleasepool { withExtendedLifetime(make()) {} } } }
        for batch in 0..<9 {
            for (name, make) in batch % 2 == 0 ? cases : cases.reversed() {
                let start = CACurrentMediaTime()
                autoreleasepool { for _ in 0..<3000 { withExtendedLifetime(make()) {} } }
                samples[name, default: []].append((CACurrentMediaTime() - start) * 1e6 / 3000)
            }
        }
        var allocations: [String: [String: Int]] = [:]
        for (name, make) in cases {
            let view = make()
            let holders = [holder(view, "menuDisposable"), holder(view, "longDisposable")].compactMap { $0 }
            allocations[name] = ["view_bytes": malloc_size(Unmanaged.passUnretained(view).toOpaque()), "holder_bytes": holders.reduce(0) { $0 + malloc_size(Unmanaged.passUnretained($1 as AnyObject).toOpaque()) }, "holder_count": holders.count]
        }
        try JSONSerialization.data(withJSONObject: ["variant": variant, "microseconds_per_operation": samples, "allocations": allocations], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/deferred-interaction-\(variant).json"))
    }
}
