import XCTest
import AppKit
import SwiftSignalKit
@testable import GalleryUI

final class GalleryImageReleaseTests: XCTestCase {

    private func pageImage() -> NSImage {
        let context = CGContext(data: nil, width: 2400, height: 1800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 1200, height: 900))
    }

    private func bindLikeAGalleryPage(_ image: Promise<GPreviewValueClass>, _ view: Promise<NSView>, received: @escaping (NSImage?) -> Void) -> Disposable {
        return combineLatest(image.get() |> map { $0.value }, view.get()).start(next: { value, view in
            if case let .image(image, _) = value {
                view.layer?.contents = image
                received(image)
            }
        })
    }

    func testReleasingWithNeverKeptThePageImageAlive() {
        let image = Promise<GPreviewValueClass>()
        let view = Promise<NSView>(NSView())
        weak var weakImage: NSImage?
        let disposable = bindLikeAGalleryPage(image, view, received: { _ in })
        autoreleasepool {
            let shown = pageImage()
            weakImage = shown
            image.set(.single(GPreviewValueClass(.image(shown, nil))))
        }
        image.set(.never())
        XCTAssertNotNil(weakImage, "combineLatest keeps the last image, so the old release freed nothing")
        disposable.dispose()
    }

    func testReleasingWithAnEmptyValueFreesThePageImage() {
        let image = Promise<GPreviewValueClass>()
        let view = Promise<NSView>(NSView())
        weak var weakImage: NSImage?
        var lastReceived: NSImage?? = .none
        let disposable = bindLikeAGalleryPage(image, view, received: { lastReceived = .some($0) })
        autoreleasepool {
            let shown = pageImage()
            weakImage = shown
            image.set(.single(GPreviewValueClass(.image(shown, nil))))
        }
        XCTAssertNotNil(weakImage)

        autoreleasepool {
            image.set(.single(GPreviewValueClass(.image(nil, nil))))
            lastReceived = nil
        }
        XCTAssertNil(weakImage, "an empty value replaces the image downstream")

        autoreleasepool {
            let again = pageImage()
            image.set(.single(GPreviewValueClass(.image(again, nil))))
        }
        if case let .some(.some(shown)) = lastReceived {
            XCTAssertEqual(shown.size, NSSize(width: 1200, height: 900), "a later request shows the page again")
        } else {
            XCTFail("the page did not receive its image again")
        }
        disposable.dispose()
    }
}
