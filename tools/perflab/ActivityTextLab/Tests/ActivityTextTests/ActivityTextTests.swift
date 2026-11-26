import AppKit
import XCTest
import TGUIKit
import ColorPalette
@testable import ActivityText

final class ActivityTextTests: XCTestCase {
    private static var images: [NSImage] = []
    private let theme = ActivitiesTheme(textColor: .blue, backgroundColor: .white)
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        locale = 0
        if Self.images.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
                image.setName(name)
                Self.images.append(image)
            }
        }
    }
    override func tearDown() {
        locale = 0
        System.updateScaleFactor(2)
    }
    private func layout(_ model: Node) -> TextViewLayout? {
        model.view?.subviews.compactMap { $0 as? TextView }.first?.textLayout
    }
    private func input(_ activity: PeerInputActivity = .typingText, name: String = "Ada") -> (PeerId, [(Peer, PeerInputActivity)]) {
        (PeerId(namespace: 2), [(TestPeer(name), activity)])
    }
    private func text(_ string: String, font: NSFont = .systemFont(ofSize: 13), color: NSColor = .blue) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }
    private func pixels(_ layout: TextViewLayout, scale: CGFloat) -> Data {
        let context = CGContext(data: nil, width: 1200, height: 150, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        for line in layout.lines {
            context.textPosition = CGPoint(x: 5 + line.frame.minX, y: 30)
            CTLineDraw(line.line, context)
        }
        return Data(bytes: context.data!, count: 720000)
    }
    private func assertEqual(_ old: TextViewLayout, _ new: TextViewLayout, scale: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(old.attributedString, new.attributedString, file: file, line: line)
        XCTAssertEqual(old.layoutSize, new.layoutSize, file: file, line: line)
        XCTAssertEqual(old.lines.map(\.range), new.lines.map(\.range), file: file, line: line)
        XCTAssertEqual(old.lines.map(\.frame), new.lines.map(\.frame), file: file, line: line)
        XCTAssertEqual(pixels(old, scale: scale), pixels(new, scale: scale), file: file, line: line)
    }
    func testRepeatedUpdatesReuseLayoutAndDeliverAllCallbacks() {
        let model = CurrentModel()
        var callbacks = 0
        model.update(with: input(), for: 220, theme: theme) { XCTAssertTrue($0); callbacks += 1 }
        let first = layout(model)
        XCTAssertNotNil(first)
        for _ in 0..<1000 {
            model.update(with: input(), for: 220, theme: theme) { XCTAssertTrue($0); callbacks += 1 }
            XCTAssertTrue(layout(model) === first)
        }
        XCTAssertEqual(callbacks, 1001)
    }
    func testProgressOnlyChangesReuseTextButActivityChangesRefreshIt() {
        let model = CurrentModel()
        model.update(with: input(.uploadingFile(progress: 0)), for: 220, theme: theme) { _ in }
        let first = layout(model)
        for progress in 1...100 {
            model.update(with: input(.uploadingFile(progress: Int32(progress))), for: 220, theme: theme) { _ in }
            XCTAssertTrue(layout(model) === first)
        }
        model.update(with: input(.recordingVoice), for: 220, theme: theme) { _ in }
        XCTAssertFalse(layout(model) === first)
        XCTAssertNotEqual(layout(model)?.attributedString, first?.attributedString)
    }
    func testNameLocaleWidthAndThemeChangesMatchOriginalModel() {
        let old = ReferenceModel(), new = CurrentModel()
        for language in 0...1 {
            locale = language
            for name in ["Ada", "Grace", "مرحبا 👨‍👩‍👧‍👦"] {
                for width in [CGFloat(50), 90, 220, 400, 220] {
                    for color in [NSColor.blue, .red] {
                        let theme = ActivitiesTheme(textColor: color, backgroundColor: .white)
                        old.update(with: input(name: name), for: width, theme: theme) { _ in }
                        new.update(with: input(name: name), for: width, theme: theme) { _ in }
                        assertEqual(layout(old)!, layout(new)!, scale: 2)
                    }
                }
            }
        }
    }
    func testEveryActivityAndGroupCombinationMatchesOriginal() {
        let activities: [PeerInputActivity] = [.typingText, .uploadingFile(progress: 10), .recordingVoice, .uploadingPhoto(progress: 20), .uploadingVideo(progress: 30), .playingGame, .recordingInstantVideo, .uploadingInstantVideo(progress: 40), .speakingInGroupCall(timestamp: 50), .choosingSticker, .interactingWithEmoji(emoticon: "🦆", messageId: MessageId(id: 1), interaction: nil), .seeingEmojiInteraction(emoticon: "🦆")]
        let old = ReferenceModel(), new = CurrentModel()
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for namespace in [Int32(0), 1, 2] {
                for activity in activities {
                    for count in 1...3 {
                        var peers: [(Peer, PeerInputActivity)] = (0..<count).map { (TestPeer("Peer \($0)"), activity) }
                        if count == 3 { peers[2] = (TestPeer("Other"), .typingText) }
                        let input = (PeerId(namespace: namespace), peers)
                        old.update(with: input, for: 180, theme: theme) { _ in }
                        new.update(with: input, for: 180, theme: theme) { _ in }
                        assertEqual(layout(old)!, layout(new)!, scale: scale)
                    }
                }
            }
        }
    }
    func testUnicodeFontsScalesAndTruncationMatchFreshMeasurement() {
        let model = CurrentModel()
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for string in ["", "Typing", "café ffi AV", "👨‍👩‍👧‍👦 🏳️‍🌈", "مرحبا بالعالم שלום", "中文 日本語 한글", String(repeating: "Long name ", count: 20)] {
                for width in [CGFloat(-1), 0, 1, 30, 130, 350] {
                    for font in [NSFont.systemFont(ofSize: 13), NSFont.boldSystemFont(ofSize: 18)] {
                        let value = text(string, font: font)
                        let reference = TextViewLayout(value, maximumNumberOfLines: 1)
                        reference.measure(width: width)
                        let current = model.activityTextLayout(value, width: width, color: .blue)
                        assertEqual(reference, current, scale: scale)
                        XCTAssertTrue(current === model.activityTextLayout(value, width: width, color: .blue))
                    }
                }
            }
        }
    }
    func testScaleAndSelectionPaletteInvalidateLayout() {
        let model = CurrentModel(), value = text("Typing")
        let first = model.activityTextLayout(value, width: 200, color: .blue)
        System.updateScaleFactor(3)
        let scaled = model.activityTextLayout(value, width: 200, color: .blue)
        XCTAssertFalse(first === scaled)
        let original = presentation
        defer { updateTheme(original) }
        updateTheme(PresentationTheme(colors: darkPalette, search: original.search, inputTheme: original.inputTheme))
        XCTAssertNotEqual(original.colors.selectText.cgColor, presentation.colors.selectText.cgColor)
        XCTAssertFalse(scaled === model.activityTextLayout(value, width: 200, color: .blue))
    }
    func testDynamicColorAppearanceInvalidatesLayout() {
        let original = NSAppearance.current
        defer { NSAppearance.current = original }
        let color = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black }
        let model = CurrentModel(), value = text("Typing", color: color)
        NSAppearance.current = NSAppearance(named: .aqua)
        let first = model.activityTextLayout(value, width: 200, color: color)
        NSAppearance.current = NSAppearance(named: .darkAqua)
        let second = model.activityTextLayout(value, width: 200, color: color)
        XCTAssertFalse(first === second)
        let reference = TextViewLayout(value, maximumNumberOfLines: 1)
        reference.measure(width: 200)
        assertEqual(reference, second, scale: 2)
    }
    func testEmptyAndCleanupDiscardCachedLayout() {
        let model = CurrentModel()
        model.update(with: input(), for: 220, theme: theme) { _ in }
        let first = layout(model)
        model.update(with: (PeerId(), []), for: 220, theme: theme) { XCTAssertFalse($0) }
        XCTAssertNil(layout(model))
        XCTAssertFalse(model.isActive)
        model.update(with: input(), for: 220, theme: theme) { _ in }
        XCTAssertFalse(layout(model) === first)
        let second = layout(model)
        model.clean()
        model.update(with: input(), for: 220, theme: theme) { _ in }
        XCTAssertFalse(layout(model) === second)
    }
    func testCacheRetainsOnlyCurrentLayoutAndModelReleasesIt() {
        weak var first: TextViewLayout?
        weak var last: TextViewLayout?
        autoreleasepool {
            let model = CurrentModel()
            autoreleasepool { first = model.activityTextLayout(text("First"), width: 200, color: .blue) }
            XCTAssertNotNil(first)
            autoreleasepool { last = model.activityTextLayout(text("Last"), width: 200, color: .blue) }
            XCTAssertNil(first)
            XCTAssertNotNil(last)
        }
        XCTAssertNil(last)
    }
    func testSelectionAndViewGeometryMatchOriginalAcrossRebinding() {
        let old = ReferenceModel(), new = CurrentModel()
        for model: Node in [old, new] {
            if let model = model as? ReferenceModel { model.update(with: input(), for: 220, theme: theme) { _ in } }
            if let model = model as? CurrentModel { model.update(with: input(), for: 220, theme: theme) { _ in } }
            let textLayout = layout(model)!
            textLayout.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: 3), color: presentation.colors.selectText, def: true)
        }
        for width in [CGFloat(220), 220, 90, 300] {
            old.update(with: input(), for: width, theme: theme) { _ in }
            new.update(with: input(), for: width, theme: theme) { _ in }
            let oldView = old.view!.subviews.compactMap { $0 as? TextView }.first!
            let newView = new.view!.subviews.compactMap { $0 as? TextView }.first!
            XCTAssertEqual(oldView.frame, newView.frame)
            XCTAssertEqual(oldView.textLayout!.selectedRange.range, newView.textLayout!.selectedRange.range)
            XCTAssertEqual(newView.textLayout!.selectedRange.range, NSRange(location: 0, length: 3))
        }
    }
    func testRasterProofIsNotBlank() {
        let model = CurrentModel()
        let layout = model.activityTextLayout(text("Typing 🦆"), width: 200, color: .blue)
        XCTAssertTrue(pixels(layout, scale: 2).contains { $0 != 0 })
    }
    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["ACTIVITY_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let iterations = 10000
        for scenario in ["unchanged", "progress", "name", "width", "cold", "empty"] {
            for pass in 0..<5 {
                var old = ReferenceModel(), new = CurrentModel()
                var sink = 0
                func run(_ baseline: Bool) -> Double {
                    let start = CFAbsoluteTimeGetCurrent()
                    for i in 0..<iterations {
                        autoreleasepool {
                            let value = scenario == "empty" ? (PeerId(), []) : input(scenario == "progress" ? .uploadingFile(progress: Int32(i % 100)) : .typingText, name: scenario == "name" ? "Peer \(i)" : "Ada")
                            let width: CGFloat = scenario == "width" ? CGFloat(180 + i % 2 * 50) : 220
                            if baseline {
                                if scenario == "cold" { old = ReferenceModel() }
                                old.update(with: value, for: width, theme: theme) { if $0 { sink += 1 } }
                            } else {
                                if scenario == "cold" { new = CurrentModel() }
                                new.update(with: value, for: width, theme: theme) { if $0 { sink += 1 } }
                            }
                        }
                    }
                    return (CFAbsoluteTimeGetCurrent() - start) * 1e6 / Double(iterations)
                }
                let baseline: Double, current: Double
                if pass % 2 == 0 { baseline = run(true); current = run(false) } else { current = run(false); baseline = run(true) }
                print("BENCH \(scenario) pass=\(pass) baseline_us=\(baseline) current_us=\(current) sink=\(sink)")
            }
        }
    }
}
