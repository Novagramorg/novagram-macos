import AppKit
import XCTest
@testable import TGUIKit

final class ImageAlphaAnalysisTests: XCTestCase {
    private func image(subject: NSColor?, transparentBorder: Bool) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 32, height: 32))
        if let subject {
            context.setFillColor(subject.cgColor)
            context.fill(transparentBorder ? CGRect(x: 14, y: 14, width: 4, height: 4) : CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testTransparentPaddingAndOpaqueImagesDoNotCauseInversion() throws {
        let opaque = try image(subject: .black, transparentBorder: false)
        XCTAssertFalse(imageHasTransparency(opaque))
        XCTAssertFalse(imageRequiresInversion(opaque))
        let empty = try image(subject: nil, transparentBorder: true)
        XCTAssertTrue(imageHasTransparency(empty))
        XCTAssertFalse(imageRequiresInversion(empty))
        for color in [NSColor.white, .red, .white.withAlphaComponent(0.125)] {
            let artwork = try image(subject: color, transparentBorder: true)
            XCTAssertTrue(imageHasTransparency(artwork))
            XCTAssertFalse(imageRequiresInversion(artwork))
        }
    }

    func testDarkVisibleArtworkStillRequiresTinting() throws {
        for alpha: CGFloat in [0.125, 0.5, 1] {
            let artwork = try image(subject: NSColor.black.withAlphaComponent(alpha), transparentBorder: true)
            XCTAssertTrue(imageHasTransparency(artwork))
            XCTAssertTrue(imageRequiresInversion(artwork))
        }
    }
}
