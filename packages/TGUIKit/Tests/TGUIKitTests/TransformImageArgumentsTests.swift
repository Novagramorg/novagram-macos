import Cocoa
import XCTest
@testable import TGUIKit

final class TransformImageArgumentsTests: XCTestCase {
    func value(corners: ImageCorners = .init(), insets: NSEdgeInsets = .init(), mode: TransformImageResizeMode = .none, size: NSSize = NSSize(width: 30, height: 40), bounds: NSSize = NSSize(width: 50, height: 60), color: TransformImageEmptyColor? = nil, scale: CGFloat = 2, mirror: Bool = false, object: Int = 0) -> TransformImageArguments {
        TransformImageArguments(corners: corners, imageSize: size, boundingSize: bounds, intrinsicInsets: insets, resizeMode: mode, emptyColor: color, scale: scale, someObject: object, mirror: mirror)
    }

    func testEveryDrawingFieldParticipatesInEquality() {
        let base = value()
        let variants = [
            value(insets: .init(top: 1, left: 0, bottom: 0, right: 0)),
            value(insets: .init(top: 0, left: 1, bottom: 0, right: 0)),
            value(insets: .init(top: 0, left: 0, bottom: 1, right: 0)),
            value(insets: .init(top: 0, left: 0, bottom: 0, right: 1)),
            value(mode: .blurBackground), value(mode: .fill(.red)),
            value(mode: .fillTransparent), value(mode: .imageColor(.blue)),
            value(size: NSSize(width: 31, height: 40)), value(bounds: NSSize(width: 50, height: 61)),
            value(color: .color(.red)), value(scale: 3), value(mirror: true), value(object: 1),
            value(corners: .init(radius: 1)),
            value(corners: .init(topLeft: .Tail(0), topRight: .Corner(0), bottomLeft: .Corner(0), bottomRight: .Corner(0)))
        ]
        XCTAssertEqual(Set([base] + variants).count, variants.count + 1)
        XCTAssertEqual(base, value())
        for (index, other) in variants.enumerated() { XCTAssertNotEqual(base, other, "field=\(index)") }
    }

    func testCornerEqualityIsExactAndTransitive() {
        let step = CGFloat.ulpOfOne * 0.75
        for make in [ImageCorner.Corner, ImageCorner.Tail] {
            XCTAssertNotEqual(make(0), make(step))
            XCTAssertNotEqual(make(step), make(step * 2))
            XCTAssertNotEqual(make(0), make(step * 2))
            XCTAssertEqual(make(0), make(-0))
        }
    }

    func testCornerKindsAndTailRadiiProduceDistinctCacheKeys() {
        let corners: [ImageCorner] = [.Corner(0), .Tail(0), .Tail(1), .Tail(2), .Tail(8), .Corner(8)]
        let values = corners.map { value(corners: .init(topLeft: .Corner(0), topRight: .Corner(0), bottomLeft: $0, bottomRight: .Corner(0))) }
        XCTAssertEqual(Set(values.map(\.hashValue)).count, values.count)
        for original in values {
            let copy = original
            XCTAssertEqual(original, copy)
            XCTAssertEqual(original.hashValue, copy.hashValue)
        }
    }
}
