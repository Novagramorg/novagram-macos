import Cocoa
import XCTest
import TGUIKit

final class FullAccessoryTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func text(_ value: String, spoiler: Bool = false, revealed: Bool = false, embedded: Bool = false) -> TextViewLayout {
        let attributed = NSMutableAttributedString(attributedString: .initialize(string: value, color: .black, font: .normal(13)))
        if spoiler { attributed.addAttribute(TextInputAttributes.spoiler, value: true, range: NSRange(location: 0, length: attributed.length)) }
        if embedded { attributed.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(42), range: NSRange(location: 0, length: 2)) }
        let layout = TextViewLayout(attributed, maximumNumberOfLines: 1, isSpoilerRevealed: revealed)
        layout.measure(width: 180)
        return layout
    }

    private func model(_ header: String = "Reply author", _ message: String = "Reply message") -> ChatAccessoryModel {
        let model = ChatAccessoryModel()
        model.header = text(header)
        model.message = text(message)
        return model
    }

    func testPlainContentUsesLayersAndMatchesNativeSize() {
        let host = View(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        let content = ChatAccessoryTextContent()
        let native = TextView()
        for value in ["", "Plain text", "مرحبا بالعالم", "你好 世界", "👨‍👩‍👧‍👦 hello"] {
            let layout = text(value)
            content.update(layout, in: host)
            native.update(layout)
            XCTAssertNil(content.nativeView)
            XCTAssertEqual(content.frame.size, native.frame.size)
            XCTAssertTrue(content.textLayout === layout)
        }
    }

    func testMissingContentClearsDrawingAndSize() {
        let host = View()
        let content = ChatAccessoryTextContent()
        content.update(text("Visible"), in: host)
        XCTAssertEqual(content.drawingLayer?.superlayer === host.layer, true)
        content.update(nil, in: host)
        XCTAssertNil(content.nativeView)
        XCTAssertNil(content.textLayout)
        XCTAssertEqual(content.frame.size, .zero)
        XCTAssertNil(content.drawingLayer)
    }

    func testSpoilersUseNativeFallbackEvenAfterReveal() throws {
        let host = View()
        let content = ChatAccessoryTextContent()
        for revealed in [false, true] {
            let layout = text("Hidden text", spoiler: true, revealed: revealed)
            content.update(layout, in: host)
            let native = try XCTUnwrap(content.nativeView)
            XCTAssertTrue(native.superview === host)
            XCTAssertTrue(native.textLayout === layout)
            XCTAssertFalse(native.isSelectable)
            XCTAssertFalse(native.userInteractionEnabled)
            XCTAssertEqual(content.frame.size, native.frame.size)
        }
    }

    func testRichToPlainRemovesNativeViewAndPreservesFrame() throws {
        let host = View()
        let content = ChatAccessoryTextContent()
        content.update(text("🐥 custom emoji", embedded: true), in: host)
        let native = try XCTUnwrap(content.nativeView)
        let frame = NSRect(origin: NSPoint(x: 13, y: 17), size: content.frame.size)
        content.updateFrame(frame, transition: .immediate)
        XCTAssertEqual(native.frame, frame)
        content.update(text("Plain"), in: host)
        XCTAssertNil(native.superview)
        XCTAssertNil(content.nativeView)
        XCTAssertEqual(content.frame.origin, frame.origin)
        XCTAssertEqual(content.drawingLayer?.superlayer === host.layer, true)
    }

    func testFullPlainAccessoryRemovesTwoViewsAndPreservesAccessibility() {
        let model = model()
        let native = NativeAccessoryView(frame: model.size.bounds)
        let current = ChatAccessoryView(frame: model.size.bounds)
        native.updateModel(model, animated: false)
        current.updateModel(model, animated: false)
        XCTAssertEqual(viewTreeCount(native) - viewTreeCount(current), 2)
        XCTAssertEqual(current.accessibilityDefaultLabel, native.accessibilityDefaultLabel)
        XCTAssertEqual(current.accessibilityDefaultLabel, "Reply author. Reply message")
        model.header = nil
        model.message = nil
        current.updateModel(model, animated: false)
        XCTAssertNil(current.accessibilityDefaultLabel)
    }

    func testFullRichAccessoryReusesAndRemovesFallbackViews() throws {
        let model = model()
        model.header = text("🐥 author", embedded: true)
        model.message = text("🐥 message", embedded: true)
        let current = ChatAccessoryView(frame: model.size.bounds)
        current.updateModel(model, animated: false)
        let header = try XCTUnwrap(current.headerView)
        let message = try XCTUnwrap(current.textView)
        current.updateModel(model, animated: false)
        XCTAssertTrue(current.headerView === header)
        XCTAssertTrue(current.textView === message)
        model.header = text("Plain author")
        model.message = text("Plain message")
        current.updateModel(model, animated: false)
        XCTAssertNil(current.headerView)
        XCTAssertNil(current.textView)
        XCTAssertNil(header.superview)
        XCTAssertNil(message.superview)
    }

    func testPlainAccessoryPixelsMatchNativeAtMultipleScales() {
        for scale: CGFloat in [1, 2, 3] {
            for message in ["Reply message", "مرحبا بالعالم", "你好 世界", "👨‍👩‍👧‍👦 hello"] {
                let model = model("Reply author", message)
                let native = NativeAccessoryView(frame: model.size.bounds)
                let current = ChatAccessoryView(frame: model.size.bounds)
                native.updateModel(model, animated: false)
                current.updateModel(model, animated: false)
                let expected = ViewSnapshot.render(native, scale: scale)
                let actual = ViewSnapshot.render(current, scale: scale)
                XCTAssertGreaterThan(expected.pixels(darkerThan: 100), 0)
                XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale), message=\(message)")
            }
        }
    }
}

extension FullAccessoryTests {
    private func asymmetricImage(_ width: CGFloat = 16, _ height: CGFloat = 12) -> CGImage {
        generateImage(NSSize(width: width, height: height), contextGenerator: { size, context in
            context.clear(size.bounds)
            context.setFillColor(NSColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 3))
            context.setFillColor(NSColor.blue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width / 4, height: size.height))
        })!
    }

    func testPollQuoteAndSideAccessoriesMatchNative() {
        for scale: CGFloat in [1, 2, 3] {
            for variant in 0..<8 {
                let model = ReplyModel()
                model.header = variant == 7 ? nil : text("Long author name with wrapping")
                model.message = variant == 6 ? nil : text("Reply message with a very long continuation")
                model.size = NSSize(width: 250, height: 70)
                model.modelType = variant & 1 == 0 ? .modern : .classic
                model.isSideAccessory = variant & 2 != 0
                model.topOffset = variant & 2 == 0 ? 0 : 9
                model.mediaInset = variant & 4 == 0 ? 0 : 26
                model.presentation.background = .white
                model.pollIcon = asymmetricImage()
                model.quoteIcon = asymmetricImage(12, 16)
                let native = NativeAccessoryView(frame: model.size.bounds)
                let current = ChatAccessoryView(frame: model.size.bounds)
                native.updateModel(model, animated: false)
                current.updateModel(model, animated: false)
                XCTAssertEqual(native.headerFrame.size, current.headerFrame.size)
                XCTAssertEqual(native.messageFrame.size, current.messageFrame.size)
                XCTAssertEqual(native.pollFrame, current.pollFrame)
                XCTAssertEqual(native.quoteFrame, current.quoteFrame)
                let expected = ViewSnapshot.render(native, scale: scale)
                let actual = ViewSnapshot.render(current, scale: scale)
                XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale), variant=\(variant)")
                model.pollIcon = nil
                model.quoteIcon = nil
                current.updateModel(model, animated: false)
                XCTAssertNil(current.pollFrame)
                XCTAssertNil(current.quoteFrame)
            }
        }
    }

    func testPatternCompositingMatchesNative() {
        let model = model()
        model.presentation.pattern = 42
        let native = NativeAccessoryView(frame: model.size.bounds)
        let current = ChatAccessoryView(frame: model.size.bounds)
        native.updateModel(model, animated: false)
        current.updateModel(model, animated: false)
        native.layoutSubtreeIfNeeded()
        current.layoutSubtreeIfNeeded()
        native.patternForTesting(asymmetricImage())
        current.patternForTesting(asymmetricImage())
        let expected = ViewSnapshot.render(native)
        let actual = ViewSnapshot.render(current)
        XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0)
    }

    func testBlockQuoteKeepsNativeRenderer() throws {
        let quote = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue))
        let value = NSAttributedString(string: "Quoted text", attributes: [.font: NSFont.systemFont(ofSize: 13), TextInputAttributes.quote: quote])
        let layout = TextViewLayout(value)
        layout.measure(width: 200)
        let host = View()
        let content = ChatAccessoryTextContent()
        content.update(layout, in: host)
        XCTAssertTrue(try XCTUnwrap(content.nativeView).textLayout === layout)
    }

    func testBackingScaleAndClickHandlerSurviveTextUpdates() throws {
        let model = model()
        let current = ChatAccessoryView(frame: model.size.bounds)
        var calls = 0
        current.set(handler: { _ in calls += 1 }, for: .Click)
        current.updateModel(model, animated: false)
        current.send(event: .Click)
        let window = SnapshotWindow(contentRect: model.size.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.scale = 3
        window.contentView = current
        current.viewDidChangeBackingProperties()
        let content = try XCTUnwrap(current.layer?.sublayers?.first { $0 is TextViewLayer })
        XCTAssertEqual(content.contentsScale, 3)
        model.message = text("New reply")
        current.updateModel(model, animated: false)
        current.send(event: .Click)
        XCTAssertEqual(calls, 2)
        window.contentView = nil
        window.close()
    }

    func testFullEmojiLifecycleReleasesObserverAndStopsPlayback() throws {
        let model = model()
        model.header = text("🐥 author", embedded: true)
        model.message = text("🐥 message", embedded: true)
        let current = ChatAccessoryView(frame: model.size.bounds)
        current.updateModel(model, animated: false)
        XCTAssertNil(current.observerForTesting)
        let window = SnapshotWindow(contentRect: model.size.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = current
        XCTAssertNotNil(current.observerForTesting)
        let header = try XCTUnwrap(current.headerLayers.first)
        let message = try XCTUnwrap(current.messageLayers.first)
        model.header = nil
        current.updateModel(model, animated: false)
        XCTAssertNil(header.superlayer)
        XCTAssertFalse(header.isPlayable)
        XCTAssertTrue(current.messageLayers.first === message)
        XCTAssertNotNil(current.observerForTesting)
        model.message = text("Plain message")
        current.updateModel(model, animated: false)
        XCTAssertFalse(message.isPlayable)
        XCTAssertNil(message.superlayer)
        XCTAssertNil(current.observerForTesting)
        window.contentView = nil
        window.close()
    }

    func testInfoButtonKeepsItsAction() throws {
        let model = SummarizeReplyModel()
        model.isSummarize = true
        model.header = text("Summary")
        model.message = text("Generated preview")
        let view = ChatAccessoryView(frame: model.size.bounds)
        view.updateModel(model, animated: false)
        let button = try XCTUnwrap(view.infoForTesting)
        button.send(event: .Click)
        XCTAssertEqual(model.infoCalls, 1)
        view.updateModel(model, animated: false)
        XCTAssertTrue(view.infoForTesting === button)
        button.send(event: .Click)
        XCTAssertEqual(model.infoCalls, 2)
        model.isSummarize = false
        view.updateModel(model, animated: false)
        XCTAssertNil(view.infoForTesting)
        XCTAssertNil(button.superview)
    }
}


extension FullAccessoryTests {
    func testAnimatedTextGeometryKeepsDrawingInsetsAtAnimationEndpoint() throws {
        let host = View()
        let content = ChatAccessoryTextContent()
        content.update(text("Animated text"), in: host)
        let drawing = try XCTUnwrap(content.drawingLayer)
        let previousPosition = drawing.position
        let previousBounds = drawing.bounds
        let next = NSRect(x: 30, y: 25, width: 180, height: 24)
        content.updateFrame(next, transition: .animated(duration: 0.2, curve: .easeOut))
        let position = try XCTUnwrap(drawing.animation(forKey: "position") as? CABasicAnimation)
        let bounds = try XCTUnwrap(drawing.animation(forKey: "bounds") as? CABasicAnimation)
        XCTAssertEqual((position.fromValue as? NSValue)?.pointValue, previousPosition)
        XCTAssertEqual((position.toValue as? NSValue)?.pointValue, drawing.position)
        XCTAssertEqual((bounds.fromValue as? NSValue)?.rectValue, previousBounds)
        XCTAssertEqual((bounds.toValue as? NSValue)?.rectValue, drawing.bounds)
        XCTAssertEqual(drawing.bounds.origin, NSPoint(x: -2, y: -3))
        XCTAssertEqual(drawing.frame, next.insetBy(dx: -2, dy: -3))
    }

    func testRichAndPlainContentReleaseWithAccessory() {
        weak var content: ChatAccessoryTextContent?
        weak var native: TextView?
        weak var drawing: TextViewLayer?
        autoreleasepool {
            let host = View()
            let value = ChatAccessoryTextContent()
            content = value
            value.update(text("Plain text"), in: host)
            drawing = value.drawingLayer
            value.update(text("🐥 emoji", embedded: true), in: host)
            native = value.nativeView
            value.update(nil, in: host)
        }
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertNil(content)
        XCTAssertNil(native)
        XCTAssertNil(drawing)
    }
}
