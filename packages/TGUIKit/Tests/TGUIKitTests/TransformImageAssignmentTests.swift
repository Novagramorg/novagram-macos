import Cocoa
import XCTest
@testable import TGUIKit

private final class AssignmentCountingLayer: CALayer {
    var assignments = 0
    override var contents: Any? { didSet { assignments += 1 } }
}

final class TransformImageAssignmentTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func makeImage(_ color: NSColor) throws -> CGImage {
        try XCTUnwrap(generateImage(CGSize(width: 16, height: 16), contextGenerator: { size, context in
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }))
    }

    func testCallbackObservesCommittedImageAndCanRepeatAssignment() throws {
        let view = TransformImageView(), image = try makeImage(.red)
        var calls = 0
        view.imageUpdated = { [weak view] value in
            calls += 1
            XCTAssertTrue(view?.image === image)
            XCTAssertTrue(view?.layer?.contents as AnyObject? === image)
            XCTAssertTrue(value as AnyObject? === image)
            if calls == 1 { view?.image = image }
        }
        view.image = image
        XCTAssertEqual(calls, 1)
        view.imageUpdated = nil
    }

    func testReentrantReplacementLeavesLatestImageInStorageAndLayer() throws {
        let view = TransformImageView(), first = try makeImage(.red), second = try makeImage(.blue)
        var seen: [CGImage?] = []
        view.imageUpdated = { [weak view] value in
            seen.append(view?.image)
            if value as AnyObject? === first { view?.image = second }
        }
        view.image = first
        XCTAssertEqual(seen.count, 2)
        XCTAssertTrue(seen.first! === first)
        XCTAssertTrue(seen.last! === second)
        XCTAssertTrue(view.image === second)
        XCTAssertTrue(view.layer?.contents as AnyObject? === second)
        view.imageUpdated = nil
    }

    func testReentrantClearLeavesImageEmpty() throws {
        let view = TransformImageView(), image = try makeImage(.red)
        var calls = 0
        view.imageUpdated = { [weak view] value in
            calls += 1
            if value != nil { view?.clear() }
        }
        view.image = image
        XCTAssertEqual(calls, 2)
        XCTAssertNil(view.image)
        XCTAssertNil(view.layer?.contents)
        XCTAssertFalse(view.hasImage)
        view.imageUpdated = nil
    }

    func testRepeatedImageRestoresExternallyChangedContentsWithoutNotifying() throws {
        let view = TransformImageView(), image = try makeImage(.red), other = try makeImage(.blue)
        var calls = 0
        view.imageUpdated = { _ in calls += 1 }
        view.image = image
        view.layer?.contents = other
        view.image = image
        XCTAssertTrue(view.layer?.contents as AnyObject? === image)
        view.layer?.contents = nil
        view.image = image
        XCTAssertTrue(view.layer?.contents as AnyObject? === image)
        XCTAssertEqual(calls, 1)
        view.image = nil
        view.layer?.contents = other
        view.image = nil
        XCTAssertNil(view.layer?.contents)
        XCTAssertEqual(calls, 2)
    }

    func testCaptureToggledFromCallbackUsesNewImage() throws {
        let view = TransformImageView(), image = try makeImage(.red)
        view.imageUpdated = { [weak view] _ in view?.preventsCapture = true }
        view.image = image
        XCTAssertTrue(view.preventsCapture)
        XCTAssertNil(view.layer?.contents)
        XCTAssertTrue(view.layer?.sublayers?.contains { $0 is CaptureProtectedContentLayer } == true)
        view.preventsCapture = false
        XCTAssertTrue(view.layer?.contents as AnyObject? === image)
        XCTAssertTrue(view.image === image)
        view.imageUpdated = nil
    }

    func testRepeatedEmptyAssignmentsDoNotMutateLayerContents() throws {
        let view = TransformImageView(), layer = AssignmentCountingLayer(), image = try makeImage(.red)
        view.layer = layer
        view.image = image
        let initial = layer.assignments
        view.image = nil
        XCTAssertEqual(layer.assignments, initial + 1)
        for _ in 0..<100 { view.image = nil }
        XCTAssertEqual(layer.assignments, initial + 1)
        view.preventsCapture = true
        let protected = layer.assignments
        for _ in 0..<100 { view.image = nil }
        XCTAssertEqual(layer.assignments, protected)
    }

    func testDistinctImagesWithIdenticalPixelsStillNotify() throws {
        let view = TransformImageView(), first = try makeImage(.red), second = try makeImage(.red)
        XCTAssertFalse(first === second)
        var calls = 0
        view.imageUpdated = { _ in calls += 1 }
        view.image = first
        view.image = second
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(view.image === second)
        XCTAssertTrue(view.layer?.contents as AnyObject? === second)
    }
}
