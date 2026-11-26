import Cocoa
import XCTest
import class TGUIKit.VisualEffect
import class TGUIKitBaseline.VisualEffect

final class MaskTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    func bitmap(_ index: Int = 0) -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.setFillColor(CGColor(gray: 1, alpha: index % 2 == 0 ? 1 : 0.6))
        context.fillEllipse(in: CGRect(x: 2, y: 3, width: 28, height: 26))
        context.clear(CGRect(x: 9 + index % 4, y: 7, width: 6, height: 18))
        return context.makeImage()!
    }

    func storedLayer(_ view: NSView, _ name: String) -> CALayer? {
        guard let value = Mirror(reflecting: view).children.first(where: { $0.label == name })?.value else { return nil }
        if let layer = value as? CALayer { return layer }
        return Mirror(reflecting: value).children.first?.value as? CALayer
    }

    func equalImage(_ a: CGImage?, _ b: CGImage?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a == nil, b == nil, file: file, line: line)
        guard let a = a, let b = b else { return }
        XCTAssertEqual(a.width, b.width, file: file, line: line)
        XCTAssertEqual(a.height, b.height, file: file, line: line)
        XCTAssertEqual(a.bytesPerRow, b.bytesPerRow, file: file, line: line)
        XCTAssertEqual(a.bitmapInfo, b.bitmapInfo, file: file, line: line)
        XCTAssertEqual(a.dataProvider!.data! as Data, b.dataProvider!.data! as Data, file: file, line: line)
    }

    func equal(_ current: TGUIKit.VisualEffect, _ reference: TGUIKitBaseline.VisualEffect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(current.frame, reference.frame, file: file, line: line)
        XCTAssertEqual(current.maskImage?.size, reference.maskImage?.size, file: file, line: line)
        equalImage(current.maskImage?.cgImage(forProposedRect: nil, context: nil, hints: nil), reference.maskImage?.cgImage(forProposedRect: nil, context: nil, hints: nil), file: file, line: line)
        let a = storedLayer(current, "overlay")!, b = storedLayer(reference, "overlay")!
        XCTAssertEqual(a.frame, b.frame, file: file, line: line)
        XCTAssertEqual(a.backgroundColor, b.backgroundColor, file: file, line: line)
        XCTAssertEqual(a.mask?.frame, b.mask?.frame, file: file, line: line)
        equalImage(a.mask?.contents as! CGImage?, b.mask?.contents as! CGImage?, file: file, line: line)
        XCTAssertTrue(a.mask?.animationKeys()?.isEmpty ?? true, file: file, line: line)
    }

    func testMaskLayerIsLazyReusedAndReleased() {
        let view = TGUIKit.VisualEffect(frame: CGRect(x: 0, y: 0, width: 64, height: 40))
        XCTAssertNil(storedLayer(view, "overlayMask"))
        for _ in 0..<100 { view.maskContents = nil; view.layout() }
        XCTAssertNil(storedLayer(view, "overlayMask"))
        let image = bitmap()
        weak var mask: CALayer?
        autoreleasepool {
            CATransaction.begin()
            view.maskContents = image
            mask = storedLayer(view, "overlayMask")
            XCTAssertNotNil(mask)
            for _ in 0..<100 { view.maskContents = image; XCTAssertTrue(mask === storedLayer(view, "overlayMask")) }
            view.maskContents = nil
            XCTAssertNil(view.maskImage)
            XCTAssertNil(storedLayer(view, "overlayMask"))
            XCTAssertNil(mask?.contents)
            CATransaction.commit()
        }
        CATransaction.flush()
        XCTAssertNil(mask)
        view.maskContents = image
        XCTAssertNotNil(storedLayer(view, "overlayMask"))
    }

    func testPixelsAndGeometryMatchThroughResizeAndReplacement() {
        let current = TGUIKit.VisualEffect(frame: .zero), reference = TGUIKitBaseline.VisualEffect(frame: .zero)
        for index in 0..<4 {
            let image = bitmap(index)
            for size in [NSSize.zero, NSSize(width: 31.5, height: 47.25), NSSize(width: 100, height: 60)] {
                for masked in [true, true, false] {
                    let frame = NSRect(origin: CGPoint(x: 4.5, y: 8), size: size)
                    current.frame = frame; reference.frame = frame
                    current.bgColor = .systemBlue; reference.bgColor = .systemBlue
                    current.maskContents = masked ? image : nil; reference.maskContents = masked ? image : nil
                    current.layout(); reference.layout()
                    equal(current, reference)
                    let resized = NSSize(width: size.width + 9, height: size.height + 4)
                    current.change(size: resized, animated: false); reference.change(size: resized, animated: false)
                    current.layout(); reference.layout()
                    equal(current, reference)
                }
            }
        }
    }

    func testNativeMaskReplacementAndMutationStillReset() {
        let current = TGUIKit.VisualEffect(frame: CGRect(x: 0, y: 0, width: 64, height: 40))
        let reference = TGUIKitBaseline.VisualEffect(frame: current.frame)
        let image = bitmap()
        for step in 0..<4 {
            current.maskContents = image; reference.maskContents = image
            if step == 0 {
                current.maskImage = NSImage(cgImage: bitmap(1), size: NSSize(width: 4, height: 5))
                reference.maskImage = NSImage(cgImage: bitmap(1), size: NSSize(width: 4, height: 5))
            } else if step == 1 {
                current.maskImage!.size = NSSize(width: 3, height: 3)
                reference.maskImage!.size = NSSize(width: 3, height: 3)
            } else if step == 2 {
                current.maskImage!.isTemplate = true; reference.maskImage!.isTemplate = true
            } else {
                for representation in current.maskImage!.representations { current.maskImage!.removeRepresentation(representation) }
                for representation in reference.maskImage!.representations { reference.maskImage!.removeRepresentation(representation) }
            }
            current.maskContents = image; reference.maskContents = image
            equal(current, reference)
            XCTAssertFalse(current.maskImage!.isTemplate)
        }
        current.maskContents = nil; reference.maskContents = nil
        current.maskImage = NSImage(cgImage: image, size: current.bounds.size)
        reference.maskImage = NSImage(cgImage: image, size: reference.bounds.size)
        current.maskContents = nil; reference.maskContents = nil
        equal(current, reference)
    }

    func item(lite: Bool, images: [CGImage?]) -> ChatRowItem {
        ChatRowItem(context: .init(lite: lite), panels: images.enumerated().map { index, image in
            MaskPanel(rect: CGRect(x: CGFloat(index) * 35, y: 5, width: 30, height: 40), cornerRadius: 5, blurTint: .systemBlue, flatColor: .systemBlue, mask: image)
        })
    }

    func render(_ view: NSView) -> CGImage {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 180, height: 130), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        view.displayIfNeeded()
        let context = CGContext(data: nil, width: 360, height: 260, bitsPerComponent: 8, bytesPerRow: 1440, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 360, height: 260))
        context.scaleBy(x: 2, y: 2)
        view.layer!.render(in: context)
        return context.makeImage()!
    }

    func testFlatPanelReuseMatchesPixelsAndRecycling() {
        let current = CandidatePanelHost(), reference = ReferencePanelHost()
        let a = bitmap(), b = bitmap(1)
        for images: [CGImage?] in [[a, nil, b], [a, nil, b], [b], [nil], [], [a, b]] {
            var item = item(lite: true, images: images)
            for offset in [CGFloat(0), 7, 0] {
                item.bubbleFrame.origin.x = offset
                current.applyCutBands(item); reference.applyCutBands(item)
                equalImage(render(current.rowView), render(reference.rowView))
                XCTAssertEqual(current.cutBandViews.map(\.frame), reference.cutBandViews.map(\.frame))
                for view in current.cutBandViews { XCTAssertTrue(view.layer?.mask?.animationKeys()?.isEmpty ?? true) }
            }
        }
        current.applyCutBands(item(lite: true, images: [a]))
        weak var mask = current.cutBandViews[0].layer?.mask
        for _ in 0..<100 { current.applyCutBands(item(lite: true, images: [b])); XCTAssertTrue(current.cutBandViews[0].layer?.mask === mask) }
        current.applyCutBands(item(lite: true, images: [nil]))
        XCTAssertNil(current.cutBandViews[0].layer?.mask)
    }

    func testFlatRasterContainsVisibleMaskedAndUnmaskedPixels() {
        let host = CandidatePanelHost(), baseline = ReferencePanelHost()
        let image = bitmap()
        host.applyCutBands(item(lite: true, images: [image]))
        baseline.applyCutBands(item(lite: true, images: [image]))
        let masked = render(host.rowView)
        equalImage(masked, render(baseline.rowView))
        host.applyCutBands(item(lite: true, images: [nil]))
        let unmasked = render(host.rowView)
        func visiblePixels(_ image: CGImage) -> Int {
            let data = image.dataProvider!.data! as Data
            return stride(from: 3, to: data.count, by: 4).filter { data[$0] > 0 }.count
        }
        XCTAssertGreaterThan(visiblePixels(masked), 100)
        XCTAssertGreaterThan(visiblePixels(unmasked), visiblePixels(masked))
    }

    func testSwitchingBlurModesAndRemovingPanelsMatches() {
        let current = CandidatePanelHost(), reference = ReferencePanelHost()
        let image = bitmap()
        for lite in [false, true, true, false, false] {
            for images: [CGImage?] in [[nil, image, nil], [nil], [], [image]] {
                current.applyCutBands(item(lite: lite, images: images)); reference.applyCutBands(item(lite: lite, images: images))
                XCTAssertEqual(current.cutBandViews.count, reference.cutBandViews.count)
                XCTAssertEqual(current.cutBandViews.map(\.frame), reference.cutBandViews.map(\.frame))
                for (a, b) in zip(current.cutBandViews, reference.cutBandViews) {
                    XCTAssertEqual(a.layer?.cornerRadius, b.layer?.cornerRadius)
                    XCTAssertEqual(a.layer?.masksToBounds, b.layer?.masksToBounds)
                    if let a = a as? TGUIKit.VisualEffect, let b = b as? TGUIKitBaseline.VisualEffect { a.layout(); b.layout(); equal(a, b) }
                }
            }
        }
    }

    func testAttachedMaskUpdateDoesNotCreateImplicitAnimations() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = CandidatePanelHost()
        window.contentView!.addSubview(host.rowView)
        let image = bitmap()
        host.applyCutBands(item(lite: true, images: [image]))
        let mask = host.cutBandViews[0].layer!.mask!
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            var item = item(lite: true, images: [bitmap(1)])
            item.panels[0].rect.size = NSSize(width: 45, height: 50)
            host.applyCutBands(item)
        }
        XCTAssertTrue(host.cutBandViews[0].layer!.mask === mask)
        XCTAssertEqual(mask.frame, host.cutBandViews[0].bounds)
        XCTAssertTrue(mask.animationKeys()?.isEmpty ?? true)
    }
}
