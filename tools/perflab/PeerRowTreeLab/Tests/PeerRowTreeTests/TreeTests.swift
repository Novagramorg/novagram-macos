import Cocoa
import XCTest
import TGUIKit
@testable import PeerRowTree

final class TreeTests: XCTestCase {
    private static var images: [NSImage] = []
    private var renderWindow: NSWindow?
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        if Self.images.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
                image.setName(name)
                Self.images.append(image)
            }
        }
    }
    override func tearDown() {
        renderWindow?.contentView = nil
        renderWindow?.close()
        renderWindow = nil
        System.updateScaleFactor(2)
    }
    private func item(_ flags: Int) -> RowItem {
        RowItem(peer: Peer(right: flags & 1 != 0, left: flags & 2 != 0), inputActivity: flags & 4 != 0 ? 1 : nil)
    }
    private func row(_ current: Bool) -> RowEnvironment {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 50)
        return current ? CurrentRow(frame: frame) : ReferenceRow(frame: frame)
    }
    private func pixels(_ row: RowEnvironment, scale: CGFloat) -> Data {
        return autoreleasepool {
            if renderWindow == nil {
                renderWindow = NSWindow(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                renderWindow!.isReleasedWhenClosed = false
            }
            let window = renderWindow!
            window.contentView = row
            defer { window.contentView = nil }
            row.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            let context = CGContext(data: nil, width: Int(300 * scale), height: Int(50 * scale), bitsPerComponent: 8, bytesPerRow: Int(1200 * scale), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: scale, y: scale)
            row.container.layer!.render(in: context)
            return Data(bytes: context.data!, count: Int(60000 * scale * scale))
        }
    }
    private func assertEqual(_ old: RowEnvironment, _ new: RowEnvironment, scale: CGFloat = 2, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(old.roles, new.roles, file: file, line: line)
        XCTAssertEqual(old.hiddenStatus, new.hiddenStatus, file: file, line: line)
        XCTAssertEqual(old.active.map(\.updates), new.active.map(\.updates), file: file, line: line)
        let originalPixels = pixels(old, scale: scale)
        XCTAssertTrue(originalPixels.contains { $0 != 0 }, file: file, line: line)
        XCTAssertEqual(originalPixels, pixels(new, scale: scale), file: file, line: line)
        for x in [CGFloat(5), 15, 25, 35, 60, 80] {
            let point = CGPoint(x: x, y: 20)
            XCTAssertEqual((old.container.hitTest(point) as? CountingControl)?.role, (new.container.hitTest(point) as? CountingControl)?.role, file: file, line: line)
        }
    }
    func testAllPresenceTransitionsPreservePixelsAndHitOrder() {
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for animated in [false, true] {
                for from in 0..<8 {
                    for to in 0..<8 {
                        let old = row(false), new = row(true)
                        for value in [from, to, to, 7, 0] {
                            old.bind(item(value), animated: animated)
                            new.bind(item(value), animated: animated)
                            assertEqual(old, new, scale: scale)
                        }
                        old.finishRemovals()
                        new.finishRemovals()
                        assertEqual(old, new, scale: scale)
                    }
                }
            }
        }
    }
    func testUnchangedBindingsAvoidEveryReattachmentButStillUpdateControls() {
        let old = row(false), new = row(true)
        old.bind(item(7)); new.bind(item(7))
        let oldMoves = old.active.map(\.moves), newMoves = new.active.map(\.moves)
        let additions = new.container.additions
        for _ in 0..<1000 { old.bind(item(7)); new.bind(item(7)) }
        XCTAssertEqual(new.container.additions, additions)
        XCTAssertEqual(new.active.map(\.moves), newMoves)
        XCTAssertEqual(old.active.map(\.moves), oldMoves.map { $0 + 1000 })
        XCTAssertEqual(new.active.map(\.updates), [1001, 1001, 1001])
        assertEqual(old, new)
    }
    func testEmptyAndSingleAccessoryAvoidReattachment() {
        for flags in [0, 1, 2, 4] {
            let new = row(true)
            new.bind(item(flags))
            let moves = new.active.map(\.moves)
            for _ in 0..<100 { new.bind(item(flags)) }
            XCTAssertEqual(new.active.map(\.moves), moves)
        }
    }
    func testExternalChildrenAndReparentedControlsRestoreOriginalOrder() {
        let old = row(false), new = row(true)
        let other = NSView()
        for value in [old, new] {
            value.bind(item(7))
            let external = CountingControl(frame: CGRect(x: 5, y: 5, width: 40, height: 30))
            external.role = "external"
            external.backgroundColor = .purple
            value.container.addSubview(external)
            other.addSubview(value.statusControl!)
            value.bind(item(7))
        }
        assertEqual(old, new)
        XCTAssertEqual(new.roles, ["avatar", "external", "right", "left", "activity"])
        let count = new.container.additions
        new.bind(item(7))
        XCTAssertEqual(new.container.additions, count)
    }
    func testSelectionThemeAndSavedMessageRulesContinueUpdating() {
        let old = row(false), new = row(true)
        for selection in [true, false, true] {
            old.isRowSelected = selection
            new.isRowSelected = selection
            for flags in 0..<8 {
                var value = item(flags)
                for step in 0..<4 {
                    value.highlightVerified = step != 1
                    value.isLookSavedMessage = step >= 2
                    value.peerId = step == 3 ? value.account.peerId : 1
                    value.customTheme = CustomTheme(accentColor: selection ? .cyan : .yellow)
                    old.bind(value); new.bind(value)
                    assertEqual(old, new)
                }
            }
        }
    }
    func testActivityDetachesAndReusesSameViewWhenResumed() {
        let new = row(true)
        new.bind(item(7))
        let activity = new.activities!.view!
        new.bind(item(3))
        XCTAssertNil(activity.superview)
        XCTAssertTrue(new.hiddenStatus)
        new.bind(item(7))
        XCTAssertTrue(new.activities!.view === activity)
        XCTAssertTrue(activity.superview === new.container)
        XCTAssertFalse(new.hiddenStatus)
        XCTAssertEqual(new.roles, ["avatar", "right", "left", "activity"])
    }
    func testWindowAttachmentAndGeometryObserversSurviveRepeatedBindings() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = document
        window.contentView = scroll
        let new = row(true)
        document.addSubview(new)
        new.bind(item(7))
        let moves = new.active.map(\.moves)
        for _ in 0..<100 { new.bind(item(7)) }
        XCTAssertEqual(new.active.map(\.moves), moves)
        for control in new.active {
            control.postsFrameChangedNotifications = true
            let count = control.geometryNotifications
            control.setFrameOrigin(CGPoint(x: control.frame.minX + 1, y: 10))
            XCTAssertEqual(control.geometryNotifications, count + 1)
        }
        new.removeFromSuperview()
        XCTAssertTrue(new.active.allSatisfy { $0.window == nil })
        document.addSubview(new)
        XCTAssertTrue(new.active.allSatisfy { $0.window === window })
    }
    func testRemovedControlsAndRowReleaseAfterTransitions() {
        weak var removed: PremiumStatusControl?
        weak var retained: View?
        autoreleasepool {
            let new = row(true)
            autoreleasepool {
                new.bind(item(7))
                removed = new.statusControl
                retained = new.activities?.view
                new.bind(item(4))
                CATransaction.flush()
            }
            XCTAssertNil(removed)
            XCTAssertNotNil(retained)
        }
        XCTAssertNil(retained)
    }
    func testRasterContainsVisibleAccessories() {
        let new = row(true)
        new.bind(item(7))
        let full = pixels(new, scale: 2)
        XCTAssertTrue(full.contains { $0 != 0 })
        new.bind(item(0))
        XCTAssertNotEqual(full, pixels(new, scale: 2))
    }
    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["TREE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        for scenario in ["empty", "single", "two_badges", "three", "attached_three", "transitions", "cold"] {
            for pass in 0..<5 {
                let iterations = 5000
                func run(_ current: Bool) -> (Double, Int) {
                    var value = row(current)
                    var window: NSWindow?
                    if scenario == "attached_three" {
                        window = NSWindow(contentRect: value.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                        window!.isReleasedWhenClosed = false
                        window!.contentView = value
                        window!.displayIfNeeded()
                    }
                    defer { window?.contentView = nil; window?.close() }
                    var sink = 0
                    let start = CFAbsoluteTimeGetCurrent()
                    for i in 0..<iterations {
                        autoreleasepool {
                            if scenario == "cold" { value = row(current) }
                            let flags = scenario == "empty" ? 0 : scenario == "single" ? 1 : scenario == "two_badges" ? 3 : scenario == "transitions" ? i % 8 : 7
                            value.bind(item(flags))
                            sink += value.container.subviews.count
                        }
                    }
                    return ((CFAbsoluteTimeGetCurrent() - start) * 1e6 / Double(iterations), sink)
                }
                let old: (Double, Int), new: (Double, Int)
                if pass % 2 == 0 { old = run(false); new = run(true) } else { new = run(true); old = run(false) }
                XCTAssertEqual(old.1, new.1)
                print("BENCH \(scenario) pass=\(pass) baseline_us=\(old.0) current_us=\(new.0) sink=\(new.1)")
            }
        }
    }
}
