import Cocoa
import XCTest
import ObjectiveC
import SwiftSignalKit
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class FormattedDateInteractionTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var menus: [ContextMenu] = []
    private var menuOwners: [NSView] = []
    private var method: Method?
    private var original: IMP?
    private var replacement: IMP?
    private var legacy = true

    override func setUpWithError() throws {
        TGUIKitTestBootstrap.install()
        legacy = System.legacyMenu
        System.legacyMenu = true
        let method = try XCTUnwrap(class_getClassMethod(NSMenu.self, #selector(NSMenu.popUpContextMenu(_:with:for:))))
        let replacement = imp_implementationWithBlock({ [weak self] (_: AnyObject, menu: NSMenu, _: NSEvent, owner: NSView) in
            if let menu = menu as? ContextMenu {
                self?.menus.append(menu)
                self?.menuOwners.append(owner)
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
        menuOwners.removeAll()
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        if let method, let original { method_setImplementation(method, original) }
        if let replacement { imp_removeBlock(replacement) }
        System.legacyMenu = legacy
    }

    private func layout(_ date: TextViewFormattedDateData, linked: Bool = false) -> TextViewLayout {
        let value = NSMutableAttributedString(string: "Tomorrow after lunch", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        value.addAttribute(TextInputAttributes.formattedDate, value: date, range: NSRange(location: 0, length: 8))
        if linked { value.addAttribute(.link, value: "https://example.com", range: NSRange(location: 0, length: 8)) }
        let layout = TextViewLayout(value)
        layout.measure(width: 240)
        return layout
    }

    private func attach(_ view: NSView) {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = View(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        window.contentView = root
        root.addSubview(view)
        windows.append(window)
    }

    private func scene(_ layout: TextViewLayout) throws -> (ChatLayerSceneView, ChatLayerTextNode) {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        let node = ChatLayerTextNode(id: "date", selectable: true)
        node.update(layout)
        try scene.root.setChildren([node])
        attach(scene)
        return (scene, node)
    }

    private let point = NSPoint(x: 12, y: 6)

    private func send(_ kind: ChatLayerPointerEvent.Kind, to scene: ChatLayerSceneView, point: NSPoint? = nil, clicks: Int = 1, modifiers: NSEvent.ModifierFlags = []) {
        let type: NSEvent.EventType = kind == .down ? .leftMouseDown : kind == .dragged ? .leftMouseDragged : .leftMouseUp
        let location = point ?? self.point
        let native = TextTests().mouse(type, location, in: scene, clicks: clicks, modifiers: modifiers)
        _ = scene.handlePointer(kind, at: location, native: native)
    }

    func testFullAndFastPreparationPreserveTypedDateMetadata() throws {
        let date = TextViewFormattedDateData(text: "Tomorrow", date: 123)
        let source = FoldingTextLayout(blocks: [.init(text: layout(date))])
        for result in [ChatLayerMessageTextPresentation(source), try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(source))] {
            XCTAssertTrue(result.nativeFeatures.isEmpty)
            XCTAssertTrue(result.blocks[0].hasFormattedDates)
        }
        let malformed = TextViewLayout(NSAttributedString(string: "Tomorrow", attributes: [.font: NSFont.systemFont(ofSize: 14), TextInputAttributes.formattedDate: "unsupported"]))
        malformed.measure(width: 240)
        let fallback = FoldingTextLayout(blocks: [.init(text: malformed)])
        XCTAssertNil(ChatLayerMessageTextPresentation.simpleText(fallback))
        XCTAssertTrue(ChatLayerMessageTextPresentation(fallback).nativeFeatures.contains(.formattedDate))
    }

    func testDateMenuMatchesNativeAndUsesSceneAsOwner() throws {
        for modifiers: NSEvent.ModifierFlags in [[], .shift, .option, .command] {
            var calls = 0
            let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) {
                calls += 1
                return [ContextMenuItem("Copy date", handler: {})]
            }
            let native = TextView(), nativeLayout = layout(date)
            native.update(nativeLayout)
            attach(native)
            native.mouseDown(with: TextTests().mouse(.leftMouseDown, point, in: native, modifiers: modifiers))
            native.mouseUp(with: TextTests().mouse(.leftMouseUp, point, in: native, modifiers: modifiers))
            let (scene, node) = try scene(layout(date))
            send(.down, to: scene, modifiers: modifiers)
            send(.up, to: scene, modifiers: modifiers)
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(menus.suffix(2).map { $0.items.map(\.title) }, [["Copy date"], ["Copy date"]])
            XCTAssertTrue(menuOwners.last === scene)
            XCTAssertEqual(node.textLayout?.selectedRange.range, nativeLayout.selectedRange.range)
            XCTAssertEqual(node.accessibilityValue, nativeLayout.attributedString.string)
        }
    }

    func testDateTakesPriorityOverLinkAndQuoteAndEmptyMenuConsumesClick() throws {
        for empty in [false, true] {
            var dates = 0, links = 0, reveals = 0, previews = 0
            let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) {
                dates += 1
                return empty ? [] : [ContextMenuItem("Copy date", handler: {})]
            }
            let text = layout(date, linked: true)
            text.interactions.processURL = { _ in links += 1 }
            text.interactions.longHoverOnLink = { _, _ in previews += 1; return nil }
            let (scene, node) = try scene(text)
            node.onTextClick = { reveals += 1; return true }
            _ = scene.handlePointer(.moved, at: point)
            XCTAssertTrue(node.cursor === NSCursor.pointingHand)
            send(.down, to: scene)
            send(.up, to: scene)
            XCTAssertEqual(dates, 1)
            XCTAssertEqual(links, 0)
            XCTAssertEqual(reveals, 0)
            XCTAssertEqual(previews, 0)
        }
    }

    func testDoubleTripleClickAndDragSelectWithoutOpeningDate() throws {
        for clicks in [2, 3] {
            var calls = 0
            let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) { calls += 1; return [] }
            let native = TextView(), nativeLayout = layout(date)
            native.update(nativeLayout)
            attach(native)
            native.mouseDown(with: TextTests().mouse(.leftMouseDown, point, in: native, clicks: clicks))
            native.mouseUp(with: TextTests().mouse(.leftMouseUp, point, in: native, clicks: clicks))
            let (scene, node) = try scene(layout(date))
            send(.down, to: scene, clicks: clicks)
            send(.up, to: scene, clicks: clicks)
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(node.textLayout?.selectedRange.range, nativeLayout.selectedRange.range)
        }
        var calls = 0
        let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) { calls += 1; return [] }
        let (scene, node) = try scene(layout(date))
        send(.down, to: scene)
        send(.dragged, to: scene, point: NSPoint(x: 90, y: 6))
        send(.up, to: scene)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(node.textLayout?.selectedRange.hasSelectText == true)
    }

    func testMutableDateReplacementAndRemovalCannotDispatchStalePress() throws {
        for remove in [false, true] {
            var first = 0, second = 0, reveals = 0
            let a = TextViewFormattedDateData(text: "Tomorrow", date: 123) { first += 1; return [] }
            let b = TextViewFormattedDateData(text: "Tomorrow", date: 456) { second += 1; return [] }
            let text = layout(a)
            let (scene, node) = try scene(text)
            node.onTextClick = { reveals += 1; return true }
            send(.down, to: scene)
            let value = try XCTUnwrap(text.attributedString as? NSMutableAttributedString)
            if remove { value.removeAttribute(TextInputAttributes.formattedDate, range: value.range) }
            else { value.addAttribute(TextInputAttributes.formattedDate, value: b, range: NSRange(location: 0, length: 8)) }
            send(.up, to: scene)
            XCTAssertEqual(first, 0)
            XCTAssertEqual(second, 0)
            XCTAssertEqual(reveals, 0)
        }
    }

    func testDateCallbackRebindingOrRemovingSceneCannotShowOldMenu() throws {
        for remove in [false, true] {
            var callback: (() -> Void)?
            let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) {
                callback?()
                return [ContextMenuItem("Stale", handler: {})]
            }
            let (scene, node) = try scene(layout(date))
            callback = { [weak scene, weak node] in
                if remove { scene?.removeFromSuperview() }
                else { node?.update(TextTests().layout("Replacement")) }
            }
            send(.down, to: scene)
            send(.up, to: scene)
            XCTAssertTrue(menus.isEmpty)
        }
    }

    func testDateCallbackMayReenterWithANewPressWithoutLosingIt() throws {
        var callback: (() -> Void)?
        var first = 0, second = 0
        let a = TextViewFormattedDateData(text: "Tomorrow", date: 123) { first += 1; callback?(); return [] }
        let b = TextViewFormattedDateData(text: "Tomorrow", date: 456) { second += 1; return [] }
        let (scene, node) = try scene(layout(a))
        callback = { [weak self, weak scene, weak node] in
            guard let self, let scene, let node else { return }
            node.update(self.layout(b))
            self.send(.down, to: scene)
        }
        send(.down, to: scene)
        send(.up, to: scene)
        send(.up, to: scene)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }

    func testNonselectableDatesAndContextClicksDoNotUseQuoteActions() throws {
        var calls = 0, reveals = 0
        let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) { calls += 1; return [] }
        let (scene, node) = try scene(layout(date))
        node.isSelectable = false
        node.onTextClick = { reveals += 1; return true }
        send(.down, to: scene)
        send(.up, to: scene)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(reveals, 0)
        let native = TextTests().mouse(.rightMouseDown, point, in: scene)
        _ = scene.handlePointer(.down, at: point, button: 1, native: native)
        XCTAssertEqual(calls, 1)
        scene.cancelInput()
        send(.down, to: scene, modifiers: .control)
        send(.up, to: scene, modifiers: .control)
        XCTAssertEqual(calls, 1)
    }

    func testNonselectablePlainSuffixBubblesToParentWhileDateRemainsInteractive() throws {
        var dates = 0
        let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) { dates += 1; return [] }
        let text = layout(date)
        let (scene, node) = try scene(text)
        node.isSelectable = false
        try scene.root.setChildren([])
        let parent = ChatLayerNode(id: "parent")
        parent.frame = scene.bounds
        parent.acceptsPointerEvents = true
        var downs = 0, ups = 0
        parent.onPointer = { event in
            if event.kind == .down { downs += 1; return true }
            if event.kind == .up { ups += 1; return true }
            return false
        }
        try parent.setChildren([node])
        try scene.root.setChildren([parent])
        let suffix = NSPoint(x: 100, y: 6)
        XCTAssertNil(text.formattedDate(at: suffix))
        XCTAssertGreaterThanOrEqual(text.findCharacterIndex(at: suffix), 8)
        send(.down, to: scene, point: suffix)
        send(.up, to: scene, point: suffix)
        XCTAssertEqual(downs, 1)
        XCTAssertEqual(ups, 1)
        XCTAssertEqual(dates, 0)
        send(.down, to: scene)
        send(.up, to: scene)
        XCTAssertEqual(dates, 1)
        XCTAssertEqual(downs, 1)
        XCTAssertEqual(ups, 1)
    }

    func testReentrantMenuRequestDuringCancellationSupersedesDateClick() throws {
        for custom in [false, true] {
            var dates = 0, starts = 0
            var cancellations: [Int] = []
            let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) {
                dates += 1
                return [ContextMenuItem("Obsolete date", handler: {})]
            }
            let text = layout(date)
            text.alwaysStaticItems = false
            let (scene, node) = try scene(text)
            let event = TextTests().mouse(.rightMouseDown, point, in: scene)
            let location = point
            let dispose: (Int) -> Void = { [weak node] request in
                cancellations.append(request)
                if request == 1 { node?.requestMenu(at: location, event: event) }
            }
            if custom {
                text.interactions.menuItems = { _ in Signal { _ in
                    starts += 1
                    let request = starts
                    return ActionDisposable { dispose(request) }
                } }
            } else {
                text.interactions.topWindow = { Signal { _ in
                    starts += 1
                    let request = starts
                    return ActionDisposable { dispose(request) }
                } }
            }
            XCTAssertTrue(node.requestMenu(at: point, event: event))
            XCTAssertEqual(starts, 1)
            send(.down, to: scene)
            send(.up, to: scene)
            XCTAssertEqual(starts, 2)
            XCTAssertEqual(cancellations, [1])
            XCTAssertEqual(dates, 0)
            XCTAssertTrue(menus.isEmpty)
            node.resetInteraction()
            XCTAssertEqual(cancellations, [1, 2])
        }
    }

    func testDateFactoryReplacementTextMenuSupersedesOuterDateMenu() throws {
        var callback: (() -> Void)?
        var dates = 0, cancellations = 0
        let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) {
            dates += 1
            callback?()
            return [ContextMenuItem("Obsolete date", handler: {})]
        }
        let text = layout(date)
        text.alwaysStaticItems = false
        let source = ValuePipe<Window?>()
        text.interactions.menuItems = { _ in .single([ContextMenuItem("Replacement text menu", handler: {})]) }
        text.interactions.topWindow = { source.signal() |> afterDisposed { cancellations += 1 } }
        let (scene, node) = try scene(text)
        let event = TextTests().mouse(.rightMouseDown, point, in: scene)
        let location = point
        callback = { [weak node] in
            XCTAssertTrue(node?.requestMenu(at: location, event: event) == true)
        }
        send(.down, to: scene)
        send(.up, to: scene)
        XCTAssertEqual(dates, 1)
        XCTAssertEqual(cancellations, 0)
        XCTAssertTrue(menus.isEmpty)
        source.putNext(nil)
        XCTAssertEqual(menus.map { $0.items.map(\.title) }, [["Replacement text menu"]])
        menus.last?.onClose()
        XCTAssertEqual(cancellations, 1)
        callback = nil
    }

    func testNestedDateFactoryKeepsInnerMenuWithoutRebindingOrRequiringTextMenus() throws {
        for mayItems in [false, true] {
            var callback: (() -> Void)?
            var calls = 0
            let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) {
                calls += 1
                let invocation = calls
                if invocation == 1 { callback?() }
                return [ContextMenuItem(invocation == 1 ? "Obsolete outer date" : "Current inner date", handler: {})]
            }
            let text = layout(date)
            text.mayItems = mayItems
            let (scene, _) = try scene(text)
            callback = { [weak self, weak scene] in
                guard let self, let scene else { return }
                self.send(.down, to: scene)
                self.send(.up, to: scene)
            }
            let previousCount = menus.count
            send(.down, to: scene)
            send(.up, to: scene)
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(menus.count, previousCount + 1)
            XCTAssertEqual(menus.last?.items.map(\.title), ["Current inner date"])
            menus.last?.onClose()
            callback = nil
        }
    }

    func testResetAndCancelledInputClearDatePress() throws {
        for reset in [false, true] {
            var calls = 0
            let date = TextViewFormattedDateData(text: "Tomorrow", date: 123) { calls += 1; return [] }
            let (scene, node) = try scene(layout(date))
            send(.down, to: scene)
            if reset { node.resetInteraction() }
            else { scene.cancelInput() }
            send(.up, to: scene)
            XCTAssertEqual(calls, 0)
        }
    }
}
