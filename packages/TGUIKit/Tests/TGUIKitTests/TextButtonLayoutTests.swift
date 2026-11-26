import AppKit
import XCTest
@testable import TGUIKit

final class TextButtonLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        System.updateScaleFactor(2)
        super.tearDown()
    }

    private func views(_ button: NSView) -> [TextView] {
        button.subviews.compactMap { $0 as? TextView }
    }

    private func pair(title: String = "Send message", subtitle: String? = "Tomorrow") -> (TextButton, LegacyTextButton) {
        let current = TextButton(frame: CGRect(x: 0, y: 0, width: 180, height: 44))
        let legacy = LegacyTextButton(frame: current.frame)
        current.autoSizeToFit = false
        legacy.autoSizeToFit = false
        current.animates = false
        legacy.animates = false
        current.set(font: .systemFont(ofSize: 14), for: .Normal)
        legacy.set(font: .systemFont(ofSize: 14), for: .Normal)
        current.set(color: .black, for: .Normal)
        legacy.set(color: .black, for: .Normal)
        current.set(text: title, for: .Normal)
        legacy.set(text: title, for: .Normal)
        current.set(subtext: subtitle, for: .Normal)
        legacy.set(subtext: subtitle, for: .Normal)
        return (current, legacy)
    }

    private func assertEquivalent(_ current: TextButton, _ legacy: LegacyTextButton, width: CGFloat = 180, file: StaticString = #filePath, line: UInt = #line) {
        let actual = current.sizeToFit(NSSize(width: 6, height: 2), NSSize(width: width, height: 44), thatFit: true)
        let expected = legacy.sizeToFit(NSSize(width: 6, height: 2), NSSize(width: width, height: 44), thatFit: true)
        current.layoutSubtreeIfNeeded()
        legacy.layoutSubtreeIfNeeded()
        XCTAssertEqual(actual, expected, file: file, line: line)
        XCTAssertEqual(current.frame, legacy.frame, file: file, line: line)
        XCTAssertEqual(current.textSize, legacy.textSize, file: file, line: line)
        XCTAssertEqual(views(current).count, views(legacy).count, file: file, line: line)
        for (a, b) in zip(views(current), views(legacy)) {
            XCTAssertEqual(a.frame, b.frame, file: file, line: line)
            XCTAssertEqual(a.textLayout?.layoutSize, b.textLayout?.layoutSize, file: file, line: line)
            XCTAssertTrue(a.textLayout!.attributedString.isEqual(to: b.textLayout!.attributedString), file: file, line: line)
        }
    }

    func testIdenticalStateUpdatesReuseTitleSubtitleAndGlyphLines() {
        let (button, _) = pair()
        let original = views(button).map { $0.textLayout! }
        let lines = original.map { $0.lines[0].line }
        for state in [ControlState.Normal, .Hover, .Highlight, .Other, .Normal] {
            button.controlState = state
            for (index, view) in views(button).enumerated() {
                XCTAssertTrue(view.textLayout === original[index])
                XCTAssertTrue(view.textLayout!.lines[0].line === lines[index])
            }
        }
    }

    func testRepeatedSettersDoNotRebuildLayouts() {
        let (button, _) = pair()
        let layouts = views(button).map { $0.textLayout! }
        for _ in 0..<20 {
            button.set(text: "Send message", for: .Normal)
            button.set(font: .systemFont(ofSize: 14), for: .Normal)
            button.set(color: .black, for: .Normal)
            button.set(subtext: "Tomorrow", for: .Normal)
        }
        XCTAssertTrue(views(button)[0].textLayout === layouts[0])
        XCTAssertTrue(views(button)[1].textLayout === layouts[1])
    }

    func testWidthOnlySizingReusesMeasuredLinesAndMatchesLegacy() {
        let (button, legacy) = pair()
        let lines = views(button).map { $0.textLayout!.lines[0].line }
        for width in [CGFloat(0), 44, 91, 180, 300, 44] {
            assertEquivalent(button, legacy, width: width)
            for (index, view) in views(button).enumerated() {
                XCTAssertTrue(view.textLayout!.lines[0].line === lines[index])
            }
        }
    }

    func testTitleChangesDoNotRebuildUnchangedSubtitle() {
        let (button, legacy) = pair()
        let old = views(button).map { $0.textLayout! }
        button.set(text: "A longer title مرحباً 👋", for: .Normal)
        legacy.set(text: "A longer title مرحباً 👋", for: .Normal)
        XCTAssertFalse(views(button)[0].textLayout === old[0])
        XCTAssertTrue(views(button)[1].textLayout === old[1])
        assertEquivalent(button, legacy)
    }

    func testFontColorSubtitleOverridesAndDisabledStatesMatchLegacy() {
        let (button, legacy) = pair()
        button.set(color: .red, for: .Hover)
        legacy.set(color: .red, for: .Hover)
        button.set(font: .boldSystemFont(ofSize: 19), for: .Hover)
        legacy.set(font: .boldSystemFont(ofSize: 19), for: .Hover)
        button.set(subtextFont: .systemFont(ofSize: 11), for: .Highlight)
        legacy.set(subtextFont: .systemFont(ofSize: 11), for: .Highlight)
        button.set(subtextColor: .green, for: .Highlight)
        legacy.set(subtextColor: .green, for: .Highlight)
        for enabled in [true, false, true] {
            button.isEnabled = enabled
            legacy.isEnabled = enabled
            for state in [ControlState.Normal, .Hover, .Highlight, .Other] {
                button.controlState = state
                legacy.controlState = state
                assertEquivalent(button, legacy)
            }
        }
        button.isSelected = true
        legacy.isSelected = true
        assertEquivalent(button, legacy)
    }

    func testStyleAndGlassTintChangesInvalidateOnlyAffectedContent() {
        let current = TextButton()
        let legacy = LegacyTextButton()
        current.set(text: "Title", for: .Normal)
        legacy.set(text: "Title", for: .Normal)
        var style = current.style
        style.font = .boldSystemFont(ofSize: 20)
        style.foregroundColor = .red
        current.style = style
        legacy.style = style
        assertEquivalent(current, legacy)
        current._glassContentTint = .blue
        legacy._glassContentTint = .blue
        current.apply(state: .Normal)
        legacy.apply(state: .Normal)
        assertEquivalent(current, legacy)
        current._glassContentTint = nil
        legacy._glassContentTint = nil
        current.apply(state: .Normal)
        legacy.apply(state: .Normal)
        assertEquivalent(current, legacy)
    }

    func testDynamicColorsBypassLayoutReuse() {
        let (button, _) = pair(subtitle: nil)
        button.set(color: .labelColor, for: .Normal)
        let original = views(button)[0].textLayout
        button.apply(state: .Normal)
        XCTAssertFalse(views(button)[0].textLayout === original)
    }

    func testBackingScaleChangeInvalidatesLayout() {
        let (button, legacy) = pair()
        let original = views(button)[0].textLayout
        System.updateScaleFactor(1)
        button.apply(state: .Normal)
        legacy.apply(state: .Normal)
        XCTAssertFalse(views(button)[0].textLayout === original)
        assertEquivalent(button, legacy)
    }

    func testExternalLayoutReplacementMutationAndResizeAreRestored() {
        let (button, legacy) = pair()
        let title = views(button)[0]
        title.textLayout?.setAttributedString(NSAttributedString(string: "External change"))
        button.apply(state: .Normal)
        assertEquivalent(button, legacy)
        title.resize(30)
        button.apply(state: .Normal)
        assertEquivalent(button, legacy)
        title.textLayout?.dropLayoutSize()
        button.apply(state: .Normal)
        assertEquivalent(button, legacy)
        title.update(TextViewLayout(NSAttributedString(string: "Replacement")))
        button.apply(state: .Normal)
        assertEquivalent(button, legacy)
        title.setFrameSize(.zero)
        button.apply(state: .Normal)
        assertEquivalent(button, legacy)
    }

    func testSizingAfterExternalLayoutChangesMatchesLegacyWithoutApplyingState() {
        let mutations: [(TextView) -> Void] = [
            { $0.textLayout?.setAttributedString(NSAttributedString.initialize(string: "Changed externally", color: .black, font: .systemFont(ofSize: 20))) },
            { $0.textLayout?.dropLayoutSize() },
            { $0.resize(30) },
            { $0.update(TextViewLayout(NSAttributedString.initialize(string: "Replacement", color: .black, font: .systemFont(ofSize: 12)))) },
            { $0.textLayout?.penFlush = 0 },
            { $0.textLayout?.maximumNumberOfLines = 2 }
        ]
        for mutate in mutations {
            let (button, legacy) = pair()
            for view in views(button) + views(legacy) { mutate(view) }
            assertEquivalent(button, legacy)
        }
        let (button, legacy) = pair()
        System.updateScaleFactor(1)
        assertEquivalent(button, legacy)
    }

    func testSeparateButtonsNeverShareMutableLayouts() {
        let (first, _) = pair()
        let (second, _) = pair()
        let a = views(first)[0].textLayout!
        let b = views(second)[0].textLayout!
        XCTAssertFalse(a === b)
        a.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: 2))
        XCTAssertNotEqual(a.selectedRange.range, b.selectedRange.range)
    }

    func testRemovingSubtitleReleasesItsLayoutAndReaddingUsesFreshContent() {
        weak var old: TextViewLayout?
        let button = autoreleasepool {
            let (button, _) = pair()
            CATransaction.begin()
            old = views(button)[1].textLayout
            button.set(subtext: nil, for: .Normal)
            CATransaction.commit()
            CATransaction.flush()
            return button
        }
        XCTAssertNil(old)
        let (_, legacy) = pair()
        button.set(subtext: "Replacement subtitle", for: .Normal)
        legacy.set(subtext: "Replacement subtitle", for: .Normal)
        assertEquivalent(button, legacy)
    }

    func testEmptyTitleAndSubtitleFallbackMatchLegacy() {
        let (button, legacy) = pair(title: "", subtitle: "Subtitle only")
        for show in [false, true] {
            button.showsSubtextWhenEmptyTitle = show
            legacy.showsSubtextWhenEmptyTitle = show
            button.set(subtext: "Hover subtitle", for: .Hover)
            legacy.set(subtext: "Hover subtitle", for: .Hover)
            button.controlState = .Hover
            legacy.controlState = .Hover
            assertEquivalent(button, legacy)
            button.set(subtext: nil, for: .Hover)
            legacy.set(subtext: nil, for: .Hover)
            assertEquivalent(button, legacy)
        }
    }

    func testUnchangedContentStillAppliesBackgroundAndStateHandlers() {
        let (button, _) = pair()
        let layout = views(button)[0].textLayout
        var calls = 0
        button.set(handler: { _ in calls += 1 }, for: ControlState.Other)
        button.set(background: .blue, for: .Hover)
        button.controlState = .Hover
        button.controlState = .Hover
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(button.layer?.backgroundColor, NSColor.blue.cgColor)
        XCTAssertTrue(views(button)[0].textLayout === layout)
    }

    func testAccessibilityPressAndLabelSurviveReusedLayouts() {
        let (button, _) = pair()
        var clicks = 0
        button.set(handler: { _ in clicks += 1 }, for: .Click)
        for _ in 0..<5 { button.controlState = .Hover }
        XCTAssertEqual(button.accessibilityDefaultLabel, "Send message")
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(clicks, 1)
        button.set(text: "Updated", for: .Normal)
        XCTAssertEqual(button.accessibilityDefaultLabel, "Updated")
    }

    func testAutomaticSizingAndMultilineContentMatchLegacy() {
        let (button, legacy) = pair()
        button.autoSizeToFit = true
        legacy.autoSizeToFit = true
        for text in ["", "A", "Line one\nLine two", "👩🏽‍💻 مرحباً 中文", String(repeating: "Long title ", count: 30)] {
            button.set(text: text, for: .Normal)
            legacy.set(text: text, for: .Normal)
            XCTAssertEqual(button.frame, legacy.frame)
            for subtitle in [nil, "", "Small", "Multiple\nlines"] as [String?] {
                button.set(subtext: subtitle, for: .Normal)
                legacy.set(subtext: subtitle, for: .Normal)
                XCTAssertEqual(button.frame, legacy.frame)
                assertEquivalent(button, legacy)
            }
        }
    }

    func testAnimatedSubtitleReplacementMatchesLegacyInWindow() {
        let (button, legacy) = pair(subtitle: nil)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 160), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView!.addSubview(button)
        window.contentView!.addSubview(legacy)
        defer {
            button.removeFromSuperview()
            legacy.removeFromSuperview()
            window.close()
        }
        button.set(subtext: "First", for: .Normal, animated: true)
        legacy.set(subtext: "First", for: .Normal, animated: true)
        assertEquivalent(button, legacy)
        let old = views(button)[1]
        let oldLegacy = views(legacy)[1]
        let title = views(button)[0].textLayout
        button.apply(state: .Normal)
        XCTAssertTrue(views(button)[0].textLayout === title)
        button.set(subtext: nil, for: .Normal, animated: true)
        legacy.set(subtext: nil, for: .Normal, animated: true)
        XCTAssertEqual(old.superview != nil, oldLegacy.superview != nil)
        let animation = old.layer?.animation(forKey: "opacity") as? CABasicAnimation
        let expected = oldLegacy.layer?.animation(forKey: "opacity") as? CABasicAnimation
        XCTAssertEqual(animation?.duration, expected?.duration)
        XCTAssertEqual(animation?.toValue as? NSNumber, expected?.toValue as? NSNumber)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertNotNil(animation)
        }
        button.set(subtext: "Replacement", for: .Normal, animated: true)
        legacy.set(subtext: "Replacement", for: .Normal, animated: true)
        XCTAssertFalse(views(button).last?.textLayout === old.textLayout)
        assertEquivalent(button, legacy)
    }

    func testRenderingMatchesLegacyForUnicodeSubtitlesDirectionsAndScales() {
        for scale in [CGFloat(1), 2] {
            System.updateScaleFactor(scale)
            for direction in [TextButtonImageDirection.left, .right, .top] {
                for subtitle in [nil, "中文 العربية 👩🏽‍💻"] as [String?] {
                    let (button, legacy) = pair(title: "Send 👋 עברית", subtitle: subtitle)
                    let icon = testImage(CGSize(width: 32, height: 32))
                    button.set(image: icon, for: .Normal)
                    legacy.set(image: icon, for: .Normal)
                    button.direction = direction
                    legacy.direction = direction
                    for width in [CGFloat(75), 230] {
                        assertEquivalent(button, legacy, width: width)
                        let actual = ViewSnapshot.render(button, scale: scale)
                        let expected = ViewSnapshot.render(legacy, scale: scale)
                        XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "\(scale), \(direction), \(width), \(subtitle ?? "nil")")
                        XCTAssertGreaterThan(actual.bytes.filter { $0 != 0 }.count, 100)
                    }
                }
            }
        }
    }
}
