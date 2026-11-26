import AppKit
import XCTest
import func TGUIKit.imageRequiresInversion
@testable import func TGUIKit.imageHasTransparency
import func TGUIKitBaseline.imageRequiresInversion
@testable import func TGUIKitBaseline.imageHasTransparency

final class AnalysisTests: XCTestCase {
    func testTransparentPaddingDoesNotTurnWhiteOrColorfulSubjectsBlack() throws {
        for format in PixelFormat.allCases {
            for color in [Pixel.white, Pixel(255, 0, 0), Pixel(0, 180, 255), Pixel(255, 255, 255, 32)] {
                let image = try fixture(width: 100, height: 100, format: format) { x, y in x >= 45 && x < 55 && y >= 45 && y < 55 ? color : .clear }
                XCTAssertFalse(TGUIKit.imageRequiresInversion(image), "\(format)")
                XCTAssertTrue(TGUIKit.imageHasTransparency(image))
            }
        }
    }

    func testDarkSubjectsRequireTransparencyAndVisibleContent() throws {
        for format in PixelFormat.allCases {
            for alpha: UInt8 in [0, 32, 128, 255] {
                for border in [false, true] {
                    let image = try fixture(width: 32, height: 17, format: format) { x, y in border && (x == 0 || y == 0) ? .clear : Pixel(0, 0, 0, alpha) }
                    XCTAssertEqual(TGUIKit.imageRequiresInversion(image), alpha > 0 && (border || alpha < 255), "\(format), \(alpha), \(border)")
                    XCTAssertEqual(TGUIKit.imageHasTransparency(image), border || alpha < 255)
                }
            }
        }
    }

    func testStrictVisiblePixelRatioAndColorThresholds() throws {
        for format in PixelFormat.allCases {
            for darkCount in [0, 16, 17, 18, 20] {
                let image = try fixture(width: 21, height: 1, format: format) { x, _ in x == 20 ? .clear : x < darkCount ? .black : .white }
                XCTAssertEqual(TGUIKit.imageRequiresInversion(image), darkCount > 17)
            }
            for (pixel, expected) in [(Pixel(63, 63, 63), true), (Pixel(64, 64, 64), false), (Pixel(50, 45, 45), false), (Pixel(50, 46, 46), true), (Pixel(64, 64, 64, 128), false), (Pixel(62, 62, 62, 128), true)] {
                let image = try fixture(width: 11, height: 1, format: format) { x, _ in x == 10 ? .clear : pixel }
                XCTAssertEqual(TGUIKit.imageRequiresInversion(image), expected, "\(format), \(pixel)")
            }
        }
    }

    func testOriginalRegressionsAreReproduced() throws {
        let opaqueBlack = try fixture(width: 8, height: 8) { _, _ in .black }
        let empty = try fixture(width: 8, height: 8) { _, _ in .clear }
        let sparseWhite = try fixture(width: 32, height: 32) { x, y in x == 16 && y == 16 ? .white : .clear }
        for image in [opaqueBlack, empty, sparseWhite] {
            XCTAssertTrue(TGUIKitBaseline.imageRequiresInversion(image))
            XCTAssertFalse(TGUIKit.imageRequiresInversion(image))
        }
        XCTAssertTrue(TGUIKitBaseline.imageHasTransparency(opaqueBlack))
        XCTAssertFalse(TGUIKit.imageHasTransparency(opaqueBlack))
    }
}
