import XCTest
import AppKit
@testable import TGUIKit

final class ModalMorphSourceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testControlSourceIsScopedToTheHandler() {
        let outer = Control()
        let inner = Control()
        var calls = 0
        inner.set(handler: { source in
            XCTAssertTrue(Control.currentEventSource === source)
            calls += 1
        }, for: .Click)
        outer.set(handler: { source in
            XCTAssertTrue(Control.currentEventSource === source)
            inner.send(event: .Click)
            XCTAssertTrue(Control.currentEventSource === source)
            calls += 1
        }, for: .Click)
        XCTAssertNil(Control.currentEventSource)
        outer.send(event: .Click)
        XCTAssertNil(Control.currentEventSource)
        XCTAssertEqual(calls, 2)
    }

    func testNestedSourcesRestoreAfterReturningAndThrowing() throws {
        enum Failure: Error { case expected }
        let outer = NSView()
        let inner = NSView()
        XCTAssertNil(ModalMorphContextSource.current)
        let result = try ModalMorphContextSource.withSource({ outer }) {
            XCTAssertTrue(ModalMorphContextSource.current?() === outer)
            XCTAssertThrowsError(try ModalMorphContextSource.withSource({ inner }) {
                XCTAssertTrue(ModalMorphContextSource.current?() === inner)
                throw Failure.expected
            })
            XCTAssertTrue(ModalMorphContextSource.current?() === outer)
            ModalMorphContextSource.withSource(nil) {
                XCTAssertNil(ModalMorphContextSource.current)
            }
            XCTAssertTrue(ModalMorphContextSource.current?() === outer)
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertNil(ModalMorphContextSource.current)
    }

    func testDeferredSourceSurvivesScopeWithoutRetainingTheControl() {
        weak var weakSource: Control?
        var deferred: (() -> NSView?)?
        autoreleasepool {
            let source = Control()
            weakSource = source
            ModalMorphContextSource.withSource({ [weak source] in source }) {
                deferred = ModalMorphContextSource.current
            }
            XCTAssertNil(ModalMorphContextSource.current)
            XCTAssertTrue(deferred?() === source)
        }
        XCTAssertNil(weakSource)
        XCTAssertNil(deferred?())
    }

    func testUnrelatedControlDoesNotInheritAModalSource() {
        let giftAction = Control()
        let unrelated = Control()
        var captured: (() -> NSView?)?
        giftAction.set(handler: { source in
            ModalMorphContextSource.withSource({ [weak source] in source }) {
                captured = ModalMorphContextSource.current
            }
        }, for: .Click)
        unrelated.set(handler: { _ in
            XCTAssertNil(ModalMorphContextSource.current)
            XCTAssertTrue(captured?() === giftAction)
        }, for: .Click)
        giftAction.send(event: .Click)
        unrelated.send(event: .Click)
    }
}
