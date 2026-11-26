import Cocoa
import XCTest
import SwiftSignalKit
import ObjectiveC
import Darwin
import TGUIKit
@testable import ChatLayerEngine

private final class NativeMenuTextView: TextView {
    override func mouseInside() -> Bool { true }
}

private extension ChatLayerTextNode {
    func rightMouseDown(with event: NSEvent) { requestMenu(at: NSPoint(x: 5, y: 5), event: event) }
}

final class TextMenuTests: XCTestCase {
    private var scenes: [ChatLayerSceneView] = []
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
        scenes.removeAll()
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
        let layout = TextTests().layout("Menu selection 🦆 and another word")
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
                let view = makeNode(), old = layout()
                var cancellations = 0
                pending(old, custom: custom, dispose: { cancellations += 1 })
                view.update(old)
                view.rightMouseDown(with: event())
                if setter { view.resetInteraction() } else { view.update(layout()) }
                XCTAssertEqual(cancellations, 1)
            }
        }
    }

    func testSameLayoutUpdatePreservesPendingMenu() {
        let view = makeNode(), layout = layout()
        var cancellations = 0
        pending(layout, custom: false, dispose: { cancellations += 1 })
        view.update(layout)
        view.rightMouseDown(with: event())
        view.update(layout)
        view.update(layout)
        XCTAssertEqual(cancellations, 0)
        view.update(nil)
        XCTAssertEqual(cancellations, 1)
    }

    func testReplacementReleasesOldLayoutRetainedByDefaultRequest() {
        let view = makeNode(), source = ValuePipe<Window?>()
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
            let view = makeNode(), layout = layout()
            var cancellations = 0
            pending(layout, custom: custom, dispose: { cancellations += 1 })
            view.update(layout)
            view.rightMouseDown(with: event())
            try! view.scene?.root.setChildren([])
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testResetDuringSourceStartDisposesReturnedSubscription() {
        for custom in [false, true] {
            let view = makeNode(), layout = layout()
            var cancellations = 0
            pending(layout, custom: custom, start: { [weak view] in view?.update(nil) }, dispose: { cancellations += 1 })
            view.update(layout)
            view.rightMouseDown(with: event())
            XCTAssertNil(view.textLayout)
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testNewRequestDuringSourceStartKeepsNewestSubscription() {
        for custom in [false, true] {
            let view = makeNode(), layout = layout(), event = event()
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
        let view = makeNode(), layout = layout(), event = event()
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
            let view = makeNode(), old = layout(), next = layout()
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
        let view = makeNode(), layout = layout(), source = ValuePipe<Window?>()
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
        let view = makeNode(), layout = layout(), source = ValuePipe<Window?>()
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
        let view = makeNode(), layout = layout(), source = ValuePipe<Window?>()
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
        let view = makeNode(), layout = layout()
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
        let view = makeNode(), old = layout(), next = layout()
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
        let view = makeNode()
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
        let view = makeNode(), layout = layout(), source = ValuePipe<Window?>()
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
        let view = makeNode(), layout = layout(), source = ValuePipe<Window?>()
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
        let view = makeNode(), layout = layout(), event = event()
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

    func testSceneWindowRemovalCancelsWithoutAnotherEmission() {
        let node = makeNode(), layout = layout()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = node.scene
        var cancellations = 0
        pending(layout, custom: false, dispose: { cancellations += 1 })
        node.update(layout)
        node.rightMouseDown(with: event())
        window.contentView = nil
        XCTAssertEqual(cancellations, 1)
    }

    func testChangingWindowCancelsButKeyChangesPreservePendingRequest() {
        let node = makeNode(), layout = layout()
        let first = Window(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        let next = Window(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        for window in [first, next] { window.isReleasedWhenClosed = false; windows.append(window) }
        first.contentView = node.scene
        var cancellations = 0
        pending(layout, custom: false, dispose: { cancellations += 1 })
        node.update(layout)
        node.rightMouseDown(with: event())
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.post(name: name, object: first)
        }
        XCTAssertEqual(cancellations, 0)
        next.contentView = node.scene
        XCTAssertEqual(cancellations, 1)
    }

    func testHiddenAndDisabledNodesRejectAndCancelDelayedResults() {
        for change in 0..<3 {
            let node = makeNode(), layout = layout(), source = ValuePipe<Window?>()
            var cancellations = 0
            layout.interactions.topWindow = { source.signal() |> afterDisposed { cancellations += 1 } }
            node.update(layout)
            node.rightMouseDown(with: event())
            if change == 0 { node.isHidden = true }
            else if change == 1 { node.isEnabled = false }
            else { node.scene?.isHidden = true }
            source.putNext(nil)
            XCTAssertTrue(menus.isEmpty)
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testRightAndControlClickRouteThroughScene() throws {
        let node = makeNode(), layout = layout(), scene = try XCTUnwrap(node.scene)
        layout.interactions.menuItems = { _ in .single([ContextMenuItem("Message action")]) }
        node.update(layout)
        for control in [false, true] {
            let native = NSEvent.mouseEvent(with: control ? .leftMouseDown : .rightMouseDown, location: scene.convert(NSPoint(x: 5, y: 5), to: nil), modifierFlags: control ? [.control] : [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            if control { scene.mouseDown(with: native) } else { scene.rightMouseDown(with: native) }
            XCTAssertEqual(menus.last?.contextItems.map(\.title), ["Message action"])
            menus.last?.onClose()
        }
        XCTAssertEqual(menus.count, 2)
        XCTAssertTrue(scene.subviews.isEmpty)
    }

    func testProtectedAndStaticUnselectedTextDoNotConsumeMenu() {
        let node = makeNode(), layout = layout()
        node.update(layout)
        layout.mayItems = false
        XCTAssertFalse(node.requestMenu(at: NSPoint(x: 5, y: 5), event: event()))
        layout.mayItems = true
        layout.alwaysStaticItems = true
        XCTAssertFalse(node.requestMenu(at: NSPoint(x: 5, y: 5), event: event()))
        layout.alwaysStaticItems = false
        XCTAssertFalse(node.requestMenu(at: NSPoint(x: -5, y: 5), event: event()))
        XCTAssertTrue(menus.isEmpty)
    }

    func testNonselectableTextCanPresentCustomActions() throws {
        let node = makeNode(), layout = layout(), scene = try XCTUnwrap(node.scene)
        node.isSelectable = false
        layout.interactions.menuItems = { _ in .single([ContextMenuItem("Message action")]) }
        node.update(layout)
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 5, y: 5), button: 1, native: event()))
        XCTAssertEqual(menus.last?.contextItems.map(\.title), ["Message action"])
    }

    func testDefaultCopyCapturesNodeHookAndSelection() throws {
        let node = makeNode(), layout = layout()
        var copies: [String] = []
        node.copyText = { copies.append($0.string) }
        node.update(layout)
        node.rightMouseDown(with: event())
        let action = try XCTUnwrap(menus.last?.contextItems.first?.handler)
        let selected = layout.selectedString.string
        node.copyText = { _ in XCTFail("Replacement callback must not run") }
        node.update(self.layout())
        action()
        XCTAssertEqual(copies, [selected])
    }

    func testResolvedLinkUsesNativeTitleAndURL() throws {
        let node = makeNode(), layout = TextTests().layout("Link label")
        layout.alwaysStaticItems = false
        layout.interactions.resolveLink = { _ in "https://example.org/resolved" }
        layout.interactions.localizeLinkCopy = { _ in "Copy test URL" }
        layout.interactions.copyAttributedString = { _ in XCTFail("Link must not copy selection"); return true }
        node.update(layout)
        node.rightMouseDown(with: event())
        let item = try XCTUnwrap(menus.last?.contextItems.first)
        XCTAssertEqual(item.title, "Copy test URL")
        let clipboard = NSPasteboard.general.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(clipboard) }
        item.handler?()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://example.org/resolved")
    }

    func testTranslationReceivesSelectionAndOwningWindow() throws {
        let node = makeNode(), layout = layout()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = node.scene
        var translated: String?
        layout.interactions.translate = { text, owner in
            translated = text
            XCTAssertTrue(owner === window)
            return ContextMenuItem("Translate selection")
        }
        node.update(layout)
        node.rightMouseDown(with: event())
        XCTAssertEqual(translated, layout.selectedString.string)
        XCTAssertEqual(menus.last?.contextItems.last?.title, "Translate selection")
    }

    func testDestroyingSceneReleasesNodeAndPendingSubscription() {
        var cancellations = 0
        weak var released: ChatLayerTextNode?
        autoreleasepool {
            let node = makeNode(), layout = layout()
            released = node
            pending(layout, custom: false, dispose: { cancellations += 1 })
            node.update(layout)
            node.rightMouseDown(with: event())
            scenes.removeAll()
        }
        XCTAssertNil(released)
        XCTAssertEqual(cancellations, 1)
    }

    func testNativeMenuParityAcrossTextLinksSelectionAndCustomActions() throws {
        var comparisons = 0
        for string in ["Menu selection 🦆 and another word", "مرحبا English שלום", "Link label"] {
            for selected in [false, true] {
                for custom in [false, true] {
                    let node = makeNode(), native = NativeMenuTextView()
                    let a = TextTests().layout(string), b = TextTests().layout(string)
                    var copiedA: [String] = [], copiedB: [String] = []
                    for layout in [a, b] {
                        layout.alwaysStaticItems = false
                        layout.interactions.localizeLinkCopy = { _ in "Copy link" }
                        if selected { layout.selectedRange.range = NSRange(location: 0, length: 2) }
                        if custom { layout.interactions.menuItems = { _ in .single([ContextMenuItem("Inspect"), ContextMenuItem("Translate")]) } }
                    }
                    a.interactions.copyAttributedString = { copiedA.append($0.string); return true }
                    b.interactions.copyAttributedString = { copiedB.append($0.string); return true }
                    native.update(a)
                    node.update(b)
                    let nativeEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: native.convert(NSPoint(x: 5, y: 5), to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
                    native.rightMouseDown(with: nativeEvent)
                    let nativeMenu = try XCTUnwrap(menus.last)
                    node.rightMouseDown(with: event())
                    let layerMenu = try XCTUnwrap(menus.last)
                    XCTAssertFalse(nativeMenu === layerMenu)
                    XCTAssertEqual(nativeMenu.contextItems.map(\.title), layerMenu.contextItems.map(\.title))
                    XCTAssertEqual(a.selectedRange.range, b.selectedRange.range)
                    nativeMenu.contextItems.first?.handler?()
                    layerMenu.contextItems.first?.handler?()
                    XCTAssertEqual(copiedA, copiedB)
                    comparisons += 1
                }
            }
        }
        XCTAssertEqual(comparisons, 12)
    }

    func testRebindingDuringSelectionNotificationCannotOpenOldMenu() {
        let node = makeNode(), old = layout(), next = layout()
        var starts = 0
        old.interactions.menuItems = { _ in starts += 1; return .single([]) }
        node.update(old)
        node.onSelectionChanged = { [weak node] _ in node?.update(next) }
        node.rightMouseDown(with: event())
        XCTAssertTrue(node.textLayout === next)
        XCTAssertEqual(starts, 0)
        XCTAssertTrue(menus.isEmpty)
    }

    private func makeNode() -> ChatLayerTextNode {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        let node = ChatLayerTextNode(id: scenes.count, selectable: true)
        scenes.append(scene)
        try! scene.root.setChildren([node])
        return node
    }
}
