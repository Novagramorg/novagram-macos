import Cocoa
import XCTest
import SwiftSignalKit
import ObjectiveC
import Darwin
@testable import TGUIKit

private final class MenuLifecycleTextView: TextView {
    override func mouseInside() -> Bool { true }
}

final class TextViewMenuLifecycleTests: XCTestCase {
    private var menus: [ContextMenu] = []
    private var windows: [NSWindow] = []
    private var method: Method?
    private var original: IMP?
    private var replacement: IMP?
    private var legacy = true

    override func setUpWithError() throws {
        TGUIKitTestBootstrap.install()
        legacy = System.legacyMenu
        System.legacyMenu = true
        let method = try XCTUnwrap(class_getClassMethod(NSMenu.self, #selector(NSMenu.popUpContextMenu(_:with:for:))))
        let replacement = imp_implementationWithBlock({ [weak self] (_: AnyObject, menu: NSMenu, _: NSEvent, _: NSView) in
            if let menu = menu as? ContextMenu {
                self?.menus.append(menu)
                menu.onShow(menu)
            }
        } as @convention(block) (AnyObject, NSMenu, NSEvent, NSView) -> Void)
        self.method = method
        self.replacement = replacement
        original = method_setImplementation(method, replacement)
    }

    override func tearDown() {
        for menu in menus { menu.onClose() }
        menus.removeAll()
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        if let method, let original { method_setImplementation(method, original) }
        if let replacement { imp_removeBlock(replacement) }
        System.legacyMenu = legacy
    }

    private func event() -> NSEvent {
        NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
    }

    private func layout() -> TextViewLayout {
        let layout = TextViewReuseTests().layout()
        layout.alwaysStaticItems = false
        return layout
    }

    private func pending(_ layout: TextViewLayout, custom: Bool, start: @escaping () -> Void = {}, dispose: @escaping () -> Void) {
        if custom {
            layout.interactions.menuItems = { _ in Signal { _ in start(); return ActionDisposable(action: dispose) } }
        } else {
            layout.interactions.topWindow = { Signal { _ in start(); return ActionDisposable(action: dispose) } }
        }
    }

    func testReplacingLayoutCancelsCustomAndDefaultRequests() {
        for custom in [false, true] {
            for setter in [false, true] {
                let view = MenuLifecycleTextView(), old = layout()
                var cancellations = 0
                pending(old, custom: custom, dispose: { cancellations += 1 })
                view.update(old)
                view.rightMouseDown(with: event())
                if setter { view.set(layout: layout()) } else { view.update(layout()) }
                XCTAssertEqual(cancellations, 1)
            }
        }
    }

    func testSameLayoutUpdatePreservesPendingMenu() {
        let view = MenuLifecycleTextView(), layout = layout()
        var cancellations = 0
        pending(layout, custom: false, dispose: { cancellations += 1 })
        view.update(layout)
        view.rightMouseDown(with: event())
        view.update(layout)
        view.set(layout: layout)
        XCTAssertEqual(cancellations, 0)
        view.update(nil)
        XCTAssertEqual(cancellations, 1)
    }

    func testReplacementReleasesOldLayoutRetainedByDefaultRequest() {
        let view = MenuLifecycleTextView(), source = ValuePipe<Window?>()
        weak var released: TextViewLayout?
        autoreleasepool {
            let old = layout()
            released = old
            old.interactions.topWindow = { source.signal() }
            view.update(old)
            view.rightMouseDown(with: event())
            view.update(layout())
        }
        XCTAssertNil(released)
    }

    func testDetachCancelsPendingMenu() {
        for custom in [false, true] {
            let view = MenuLifecycleTextView(), layout = layout()
            windows.append(TextViewReuseTests().window(view))
            var cancellations = 0
            pending(layout, custom: custom, dispose: { cancellations += 1 })
            view.update(layout)
            view.rightMouseDown(with: event())
            view.removeFromSuperview()
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testResetDuringSourceStartDisposesReturnedSubscription() {
        for custom in [false, true] {
            let view = MenuLifecycleTextView(), layout = layout()
            var cancellations = 0
            pending(layout, custom: custom, start: { [weak view] in _ = view?.resetForContentChange() }, dispose: { cancellations += 1 })
            view.update(layout)
            view.rightMouseDown(with: event())
            XCTAssertNil(view.textLayout)
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testNewRequestDuringSourceStartKeepsNewestSubscription() {
        for custom in [false, true] {
            let view = MenuLifecycleTextView(), layout = layout(), event = event()
            var starts = 0, cancellations: [Int] = []
            if custom {
                layout.interactions.menuItems = { _ in Signal { [weak view] _ in
                    starts += 1
                    let request = starts
                    if request == 1 { view?.rightMouseDown(with: event) }
                    return ActionDisposable { cancellations.append(request) }
                } }
            } else {
                layout.interactions.topWindow = { Signal { [weak view] _ in
                    starts += 1
                    let request = starts
                    if request == 1 { view?.rightMouseDown(with: event) }
                    return ActionDisposable { cancellations.append(request) }
                } }
            }
            view.update(layout)
            view.rightMouseDown(with: event)
            XCTAssertEqual(starts, 2)
            XCTAssertEqual(cancellations, [1])
            view.update(nil)
            XCTAssertEqual(cancellations, [1, 2])
        }
    }

    func testNewRequestDuringDisposalSupersedesOuterRequest() {
        let view = MenuLifecycleTextView(), layout = layout(), event = event()
        var starts = 0, cancellations: [Int] = []
        layout.interactions.topWindow = { Signal { [weak view] _ in
            starts += 1
            let request = starts
            return ActionDisposable {
                cancellations.append(request)
                if request == 1 { view?.rightMouseDown(with: event) }
            }
        } }
        view.update(layout)
        view.rightMouseDown(with: event)
        view.rightMouseDown(with: event)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(cancellations, [1])
        view.update(nil)
        XCTAssertEqual(cancellations, [1, 2])
    }

    func testFactoryRebindingDoesNotStartObsoleteWork() {
        for custom in [false, true] {
            let view = MenuLifecycleTextView(), old = layout(), next = layout()
            var starts = 0
            if custom {
                old.interactions.menuItems = { [weak view] _ in
                    view?.update(next)
                    return Signal { _ in starts += 1; return EmptyDisposable }
                }
            } else {
                old.interactions.topWindow = { [weak view] in
                    view?.update(next)
                    return Signal { _ in starts += 1; return EmptyDisposable }
                }
            }
            view.update(old)
            view.rightMouseDown(with: event())
            XCTAssertTrue(view.textLayout === next)
            XCTAssertEqual(starts, 0)
        }
    }

    func testClosingMenuStopsStreamingSource() throws {
        let view = MenuLifecycleTextView(), layout = layout(), source = ValuePipe<Window?>()
        var cancellations = 0
        layout.interactions.menuItems = { _ in .single([]) }
        layout.interactions.topWindow = { source.signal() |> afterDisposed { cancellations += 1 } }
        view.update(layout)
        view.rightMouseDown(with: event())
        source.putNext(nil)
        let menu = try XCTUnwrap(menus.last)
        menu.onClose()
        XCTAssertEqual(cancellations, 1)
        source.putNext(nil)
        XCTAssertEqual(menus.count, 1)
    }

    func testOldMenuCloseDoesNotCancelNewRequest() throws {
        let view = MenuLifecycleTextView(), layout = layout(), source = ValuePipe<Window?>()
        var cancellations = 0
        layout.interactions.menuItems = { _ in .single([]) }
        layout.interactions.topWindow = { source.signal() |> afterDisposed { cancellations += 1 } }
        view.update(layout)
        view.rightMouseDown(with: event())
        source.putNext(nil)
        let first = try XCTUnwrap(menus.last)
        view.rightMouseDown(with: event())
        XCTAssertEqual(cancellations, 1)
        first.onClose()
        XCTAssertEqual(cancellations, 1)
        source.putNext(nil)
        XCTAssertEqual(menus.count, 2)
        menus.last?.onClose()
        XCTAssertEqual(cancellations, 2)
    }

    func testQueuedDefaultResultCannotPresentAfterReuse() {
        let view = MenuLifecycleTextView(), layout = layout(), source = ValuePipe<Window?>()
        layout.interactions.topWindow = { source.signal() }
        view.update(layout)
        view.rightMouseDown(with: event())
        let enqueued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { source.putNext(nil); enqueued.signal() }
        XCTAssertEqual(enqueued.wait(timeout: .now() + 2), .success)
        view.update(self.layout())
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(menus.isEmpty)
    }

    func testMutableTextChangeCancelsPendingMenu() throws {
        let view = MenuLifecycleTextView(), layout = layout()
        var cancellations = 0
        pending(layout, custom: false, dispose: { cancellations += 1 })
        view.update(layout)
        view.rightMouseDown(with: event())
        let text = try XCTUnwrap(layout.attributedString as? NSMutableAttributedString)
        text.replaceCharacters(in: text.range, with: "Changed content")
        layout.setAttributedString(text)
        layout.measure(width: 240)
        view.update(layout)
        XCTAssertEqual(cancellations, 1)
    }

    func testCopyActionCannotReadReplacementLayout() throws {
        let view = MenuLifecycleTextView(), old = layout(), next = layout()
        var originalCopies = 0, replacementCopies = 0
        old.interactions.copy = { originalCopies += 1; return true }
        next.interactions.copy = { replacementCopies += 1; return true }
        view.update(old)
        view.rightMouseDown(with: event())
        let menu = try XCTUnwrap(menus.last)
        let copy = try XCTUnwrap(menu.contextItems.first?.handler)
        copy()
        XCTAssertEqual(originalCopies, 1)
        view.update(next)
        copy()
        XCTAssertEqual(replacementCopies, 0)
        XCTAssertEqual(originalCopies, 2)
    }

    func testCopyActionKeepsOriginalSelectionWithoutRetainingLayout() throws {
        let view = MenuLifecycleTextView()
        var copied: [String] = []
        var expected = ""
        weak var released: TextViewLayout?
        autoreleasepool {
            let original = layout()
            released = original
            original.interactions.copyAttributedString = { copied.append($0.string); return true }
            view.update(original)
            view.rightMouseDown(with: event())
            expected = original.selectedString.string
            original.selectedRange.range = NSRange(location: 0, length: 1)
            menus.last?.contextItems.first?.handler?()
            view.update(layout())
        }
        XCTAssertNil(released)
        let copy = try XCTUnwrap(menus.last?.contextItems.first?.handler)
        copy()
        XCTAssertEqual(copied, [expected, expected])
    }

    func testOlderMenuFromSameStreamCannotCancelLatestMenu() throws {
        let view = MenuLifecycleTextView(), layout = layout(), source = ValuePipe<Window?>()
        var cancellations = 0
        layout.interactions.menuItems = { _ in .single([]) }
        layout.interactions.topWindow = { source.signal() |> afterDisposed { cancellations += 1 } }
        view.update(layout)
        view.rightMouseDown(with: event())
        source.putNext(nil)
        let first = try XCTUnwrap(menus.last)
        source.putNext(nil)
        XCTAssertEqual(menus.count, 2)
        first.onClose()
        XCTAssertEqual(cancellations, 0)
        menus.last?.onClose()
        XCTAssertEqual(cancellations, 1)
    }

    func testTextMutationWithoutUpdateRejectsDelivery() throws {
        let view = MenuLifecycleTextView(), layout = layout(), source = ValuePipe<Window?>()
        var cancellations = 0
        layout.interactions.topWindow = { source.signal() |> afterDisposed { cancellations += 1 } }
        view.update(layout)
        view.rightMouseDown(with: event())
        let text = try XCTUnwrap(layout.attributedString as? NSMutableAttributedString)
        text.replaceCharacters(in: text.range, with: "Changed content")
        source.putNext(nil)
        XCTAssertTrue(menus.isEmpty)
        XCTAssertEqual(cancellations, 1)
    }

    func testSynchronousCompletionDisposalCanStartNewRequest() {
        let view = MenuLifecycleTextView(), layout = layout(), event = event()
        var starts = 0, cancellations: [Int] = []
        layout.interactions.topWindow = { Signal { [weak view] subscriber in
            starts += 1
            let request = starts
            if request == 1 { subscriber.putNext(nil); subscriber.putCompletion() }
            return ActionDisposable {
                cancellations.append(request)
                if request == 1 { view?.rightMouseDown(with: event) }
            }
        } }
        view.update(layout)
        view.rightMouseDown(with: event)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(cancellations, [1])
        view.update(nil)
        XCTAssertEqual(cancellations, [1, 2])
    }

    func testMenuDisposalCanStartPreviewOnNewBinding() {
        let view = MenuLifecycleTextView(), old = layout(), next = TextViewReuseTests().layout(link: true)
        windows.append(TextViewReuseTests().window(view))
        let preview = expectation(description: "New preview")
        next.interactions.longHoverOnLink = { _, _ in preview.fulfill(); return nil }
        pending(old, custom: false, dispose: { [weak view] in
            guard let view else { return }
            view.update(next)
            view.checkCursor(TextViewReuseTests().event(.mouseMoved, view: view))
        })
        view.update(old)
        view.rightMouseDown(with: event())
        view.update(layout())
        XCTAssertTrue(view.textLayout === next)
        wait(for: [preview], timeout: 3)
    }

    func testPreviewDisposalCanStartMenuOnNewBinding() {
        let view = MenuLifecycleTextView(), old = TextViewReuseTests().layout(link: true), next = layout(), event = event()
        windows.append(TextViewReuseTests().window(view))
        let preview = expectation(description: "Old preview")
        var starts = 0, cancellations = 0
        pending(next, custom: false, start: { starts += 1 }, dispose: { cancellations += 1 })
        old.interactions.longHoverOnLink = { [weak view] _, _ in
            preview.fulfill()
            return ActionDisposable {
                view?.update(next)
                view?.rightMouseDown(with: event)
            }
        }
        view.update(old)
        view.checkCursor(TextViewReuseTests().event(.mouseMoved, view: view))
        wait(for: [preview], timeout: 3)
        view.update(layout())
        XCTAssertTrue(view.textLayout === next)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(cancellations, 0)
        view.update(nil)
        XCTAssertEqual(cancellations, 1)
    }

    func testCancellationAndCompletionReleaseSnapshotAttributes() {
        for completes in [false, true] {
            let view = MenuLifecycleTextView()
            weak var released: NSObject?
            autoreleasepool {
                let payload = NSObject()
                released = payload
                let text = NSMutableAttributedString(string: "Message", attributes: [.font: NSFont.systemFont(ofSize: 14), NSAttributedString.Key("MenuSnapshotPayload"): payload])
                let old = TextViewLayout(text)
                old.measure(width: 240)
                old.interactions.topWindow = { completes ? .complete() : .never() }
                view.update(old)
                view.rightMouseDown(with: event())
                view.update(layout())
            }
            XCTAssertNil(released)
        }
    }

    func testResolvedURLMenuDoesNotRetainUnusedCopyData() {
        let view = MenuLifecycleTextView()
        weak var released: NSObject?
        autoreleasepool {
            let payload = NSObject()
            released = payload
            let text = NSMutableAttributedString(string: "Link", attributes: [.font: NSFont.systemFont(ofSize: 14), .link: "https://example.com", NSAttributedString.Key("MenuSnapshotPayload"): payload])
            let original = TextViewLayout(text)
            original.measure(width: 240)
            original.interactions.resolveLink = { $0 as? String }
            original.interactions.copy = { withExtendedLifetime(payload) {}; return true }
            original.interactions.copyAttributedString = { _ in withExtendedLifetime(payload) {}; return true }
            view.update(original)
            view.rightMouseDown(with: event())
            XCTAssertEqual(menus.count, 1)
            view.update(layout())
        }
        XCTAssertNil(released)
    }

    func testMenuStateAllocationAndUpdateCost() throws {
        guard let phase = ProcessInfo.processInfo.environment["TEXT_MENU_BENCHMARK"] else { throw XCTSkip("Opt-in text menu benchmark") }
        let view = MenuLifecycleTextView(), first = layout(), next = layout()
        XCTAssertNil(DeferredInteractionTests().holder(view, "menuDisposable"))
        for _ in 0..<1000 { view.update(first); view.update(next) }
        var samples: [Double] = []
        for _ in 0..<9 {
            let start = CACurrentMediaTime()
            for _ in 0..<5000 { view.update(first); view.update(next) }
            samples.append((CACurrentMediaTime() - start) * 1e6 / 10000)
        }
        pending(first, custom: false, dispose: {})
        view.update(first)
        view.rightMouseDown(with: event())
        let state = try XCTUnwrap(DeferredInteractionTests().holder(view, "menuDisposable"))
        let report: [String: Any] = ["unit": "microseconds_per_idle_update", "samples": samples, "view_bytes": malloc_size(Unmanaged.passUnretained(view).toOpaque()), "instance_size": class_getInstanceSize(TextView.self), "used_menu_state_bytes": malloc_size(Unmanaged.passUnretained(state as AnyObject).toOpaque())]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: "/tmp/text-menu-\(phase).json"))
    }

}
