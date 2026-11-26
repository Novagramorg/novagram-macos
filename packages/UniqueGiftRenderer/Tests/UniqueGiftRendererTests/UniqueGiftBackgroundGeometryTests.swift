import XCTest
@testable import UniqueGiftRenderer

final class UniqueGiftBackgroundGeometryTests: XCTestCase {
    private func sizes(width: CGFloat) -> [Int] {
        let geometry = UniqueGiftBackgroundGeometry(size: CGSize(width: width, height: width), patternCenter: CGPoint(x: width / 2.0, y: width / 2.0), defaultHeight: width)
        return geometry.patternItems().map { Int($0.frame.width) }
    }

    func testGiftCellsKeepTheCompactRingAtAnyWidth() {
        let narrow = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 149.0, height: 128.0), giftCenterY: 60.0, cornerRadius: 10.0)
        let wide = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 178.0, height: 128.0), giftCenterY: 60.0, cornerRadius: 10.0)
        let huge = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 320.0, height: 128.0), giftCenterY: 60.0, cornerRadius: 10.0)
        XCTAssertEqual(narrow.patternDensity, .compact)
        XCTAssertEqual(wide.patternDensity, .compact)
        XCTAssertEqual(huge.patternDensity, .compact)
        func offsets(_ geometry: UniqueGiftBackgroundGeometry) -> [[Int]] {
            return geometry.patternItems().map { item in
                let frame = item.frame.offsetBy(dx: -geometry.patternCenter.x, dy: -geometry.patternCenter.y)
                return [frame.minX, frame.minY, frame.width, frame.height].map { Int(($0 * 1000.0).rounded()) }
            }
        }
        XCTAssertEqual(offsets(narrow), offsets(wide))
        XCTAssertEqual(offsets(narrow), offsets(huge))
        XCTAssertEqual(UniqueGiftBackgroundGeometry.item(size: CGSize(width: 60.0, height: 60.0), giftCenterY: 30.0, cornerRadius: 10.0).patternDensity, .small)
        XCTAssertEqual(UniqueGiftBackgroundGeometry.message(size: CGSize(width: 212.0, height: 232.0), patternCenterY: 113.0, cornerRadius: 20.0).patternDensity, .regular)
        XCTAssertEqual(UniqueGiftBackgroundGeometry.header(size: CGSize(width: 340.0, height: 278.0)).patternDensity, .regular)
    }

    func testItemSizesMatchIOS() {
        XCTAssertEqual(sizes(width: 200.0), [24, 18, 24, 19, 25, 22, 20, 20, 20, 25, 19, 18, 18, 18, 20, 18, 22, 18, 22, 24, 21, 18, 22, 23, 20, 18, 23, 20, 19, 22])
        XCTAssertEqual(sizes(width: 114.0), [20, 15, 20, 16, 20, 18, 17, 16, 17, 20, 15, 15, 15, 15, 16, 15, 18, 15, 18, 20, 17, 15, 18, 19, 17, 15, 19, 16, 16, 18])
        XCTAssertEqual(sizes(width: 60.0), [9, 7, 9, 7, 10, 9, 8, 8, 8, 10, 7, 7, 7, 7, 8, 7, 9, 7, 9, 9, 8, 7, 8, 9, 8, 7, 9, 8, 7, 9])
    }

    func testRingDistancesAndAnglesMatchIOS() {
        let center = CGPoint(x: 100.0, y: 104.0)
        let geometry = UniqueGiftBackgroundGeometry(size: CGSize(width: 200.0, height: 240.0), patternCenter: center, defaultHeight: 300.0)
        let items = geometry.patternItems()
        XCTAssertEqual(items.count, 30)
        for (index, item) in items.enumerated() {
            let row = index / 6
            let column = index % 6
            let dx = item.frame.midX - center.x
            let dy = item.frame.midY - center.y
            XCTAssertEqual(sqrt(dx * dx + dy * dy), 72.0 + CGFloat(row) * 28.0, accuracy: 0.001)
            var angle = -90.0 + Double(column) * 60.0
            if row % 2 != 0 {
                angle += 30.0
            }
            let expected = angle * .pi / 180.0
            XCTAssertEqual(dx, 0.0 + cos(expected) * (72.0 + Double(row) * 28.0), accuracy: 0.001)
            XCTAssertEqual(dy, sin(expected) * (72.0 + Double(row) * 28.0), accuracy: 0.001)
            XCTAssertEqual(item.alpha, 1.0)
        }
    }

    func testSmallSizesScaleDistances() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 114.0, height: 114.0), giftCenterY: 57.0, cornerRadius: 16.0)
        let first = geometry.patternItems()[0]
        XCTAssertEqual(57.0 - first.frame.midY, 43.2, accuracy: 0.001)
        let tiny = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 60.0, height: 60.0), giftCenterY: 30.0, cornerRadius: 0.0)
        XCTAssertEqual(30.0 - tiny.patternItems()[0].frame.midY, 25.2, accuracy: 0.001)
    }

    func testGradientGeometryOfAnOptionCell() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 110.0, height: 154.0), giftCenterY: 60.0, cornerRadius: 16.0)
        XCTAssertEqual(geometry.gradientFrame, CGRect(x: -22.0, y: 0.0, width: 154.0, height: 154.0))
        XCTAssertEqual(geometry.gradientEllipse.center.x, 55.0, accuracy: 0.001)
        XCTAssertEqual(geometry.gradientEllipse.center.y, 60.0, accuracy: 0.001)
        XCTAssertEqual(geometry.gradientEllipse.radii.width, 77.0, accuracy: 0.001)
        XCTAssertEqual(geometry.gradientEllipse.radii.height, 94.0, accuracy: 0.001)
        XCTAssertEqual(geometry.patternTintEllipse.radii, CGSize(width: 190.0, height: 77.0))
    }

    func testGradientGeometryOfAHeader() {
        let geometry = UniqueGiftBackgroundGeometry.header(size: CGSize(width: 390.0, height: 240.0))
        XCTAssertEqual(geometry.gradientFrame, CGRect(x: 45.0, y: 0.0, width: 300.0, height: 300.0))
        XCTAssertEqual(geometry.gradientEllipse.center, CGPoint(x: 195.0, y: 104.0))
        XCTAssertEqual(geometry.gradientEllipse.radii, CGSize(width: 150.0, height: 196.0))
        XCTAssertEqual(geometry.patternTintEllipse.radii, CGSize(width: 190.0, height: 150.0))
    }

    func testProfileGradientUsesTheFullWidth() {
        let geometry = UniqueGiftBackgroundGeometry.profile(size: CGSize(width: 400.0, height: 254.0), avatarCenter: CGPoint(x: 200.0, y: 110.0), avatarSize: 100.0, defaultHeight: 254.0, gradientCenter: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(geometry.gradientEllipse.center, CGPoint(x: 200.0, y: 127.0))
        XCTAssertEqual(geometry.gradientEllipse.radii, CGSize(width: 200.0, height: 127.0))
    }

    func testCollapseMovesItemsInwardAndFadesThem() {
        let geometry = UniqueGiftBackgroundGeometry.profile(size: CGSize(width: 400.0, height: 254.0), avatarCenter: CGPoint(x: 200.0, y: 110.0), avatarSize: 100.0, defaultHeight: 254.0, gradientCenter: CGPoint(x: 0.5, y: 0.5))
        let rest = geometry.patternItems(transitionFraction: 0.0)
        let collapsed = geometry.patternItems(transitionFraction: 1.0)
        XCTAssertTrue(rest.allSatisfy { $0.alpha == 1.0 })
        for item in collapsed {
            XCTAssertEqual(item.alpha, 0.0, accuracy: 0.001)
            XCTAssertEqual(hypot(item.frame.midX - 200.0, item.frame.midY - 110.0), 20.0, accuracy: 0.001)
        }
        let half = geometry.patternItems(transitionFraction: 0.4)
        XCTAssertTrue(half.contains { $0.alpha > 0.0 && $0.alpha < 1.0 })
    }

    func testColorsIgnoreTheTopByte() {
        let colors = UniqueGiftColors(center: Int32(bitPattern: 0xff336699), edge: -1, pattern: 0x000102)
        XCTAssertEqual(colors.center, 0x336699)
        XCTAssertEqual(colors.edge, 0xffffff)
        XCTAssertEqual(colors.pattern, 0x000102)
    }
}
