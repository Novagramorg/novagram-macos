import Cocoa
import XCTest
@testable import TGUIKit

final class UpdateTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func value(_ text: String = "12 participants online", count: String = "12", width: CGFloat = 240, kerned: Bool = false, rolling: Bool = false) -> DynamicCounterTextView.Value {
        DynamicCounterTextView.make(for: text, count: count, font: .normal(13), textColor: .black, width: width, kerned: kerned, rolling: rolling)
    }

    private func ordered(_ view: DynamicCounterTextView) -> [TextView] {
        view.effectiveSubviews.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func assertMatchesFresh(_ view: DynamicCounterTextView, value: DynamicCounterTextView.Value, file: StaticString = #filePath, line: UInt = #line) throws {
        let fresh = DynamicCounterTextView(frame: .zero)
        fresh.update(value, animated: false)
        XCTAssertEqual(ordered(view).map { $0.frame }, ordered(fresh).map { $0.frame }, file: file, line: line)
        XCTAssertEqual(ordered(view).map { $0.textLayout?.layoutSize }, ordered(fresh).map { $0.textLayout?.layoutSize }, file: file, line: line)
        XCTAssertEqual(view.accessibilityText, fresh.accessibilityText, file: file, line: line)
        XCTAssertEqual(view.subviews.count, fresh.subviews.count, file: file, line: line)
        XCTAssertEqual(try render(view.effectiveSubviews), try render(fresh.effectiveSubviews), file: file, line: line)
    }

    func testSameTextFollowsNarrowerAndWiderWidths() throws {
        let view = DynamicCounterTextView(frame: .zero)
        view.update(value(), animated: false)
        let original = Set(view.effectiveSubviews.map(ObjectIdentifier.init))
        for width: CGFloat in [50, 200, 80, 240] {
            let next = value(width: width)
            view.update(next, animated: false)
            try assertMatchesFresh(view, value: next)
            XCTAssertEqual(Set(view.effectiveSubviews.map(ObjectIdentifier.init)), original)
        }
    }

    func testSameTextFollowsKernedOffsets() throws {
        let view = DynamicCounterTextView(frame: .zero)
        for kerned in [false, true, false] {
            let next = value("11111", count: "11111", kerned: kerned)
            view.update(next, animated: false)
            try assertMatchesFresh(view, value: next)
        }
    }

    func testChangedNumberUpdatesReusedPrefixLayout() throws {
        let view = DynamicCounterTextView(frame: .zero)
        view.update(value("Participants 11", count: "11"), animated: false)
        let prefix = try XCTUnwrap(ordered(view).first)
        let next = value("Participants 12", count: "12", width: 60)
        view.update(next, animated: false)
        XCTAssertTrue(view.effectiveSubviews.contains { $0 === prefix })
        try assertMatchesFresh(view, value: next)
    }

    func testModeSwitchRemovesPreviousModeViews() throws {
        let view = DynamicCounterTextView(frame: .zero)
        for rolling in [false, true, false, true] {
            let next = value(rolling: rolling)
            view.update(next, animated: false)
            try assertMatchesFresh(view, value: next)
        }
    }

    func testClearAfterModeSwitchReleasesSubviews() {
        let view = DynamicCounterTextView(frame: .zero)
        view.update(value(), animated: false)
        view.update(value(rolling: true), animated: false)
        view.update(value("", count: "", rolling: false), animated: false)
        XCTAssertTrue(view.effectiveSubviews.isEmpty)
        XCTAssertTrue(view.subviews.isEmpty)
        XCTAssertEqual(view.accessibilityText, "")
    }

    func testRemeasuredValueRefreshesSubviewGeometry() throws {
        let view = DynamicCounterTextView(frame: .zero)
        let current = value("Long label", count: "")
        view.update(current, animated: false)
        current.values[0].0.measure(width: 25)
        view.update(current, animated: false)
        try assertMatchesFresh(view, value: current)
    }

    func testRepeatedEqualValuesRetainViewsAndExistingAnimation() throws {
        for rolling in [false, true] {
            let view = DynamicCounterTextView(frame: .zero)
            view.update(value(rolling: rolling), animated: false)
            let before = Set(view.effectiveSubviews.map(ObjectIdentifier.init))
            let first = try XCTUnwrap(view.effectiveSubviews.first)
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.25
            animation.toValue = 1.0
            animation.duration = 30
            first.layer?.add(animation, forKey: "labSentinel")
            for _ in 0..<5 {
                view.update(value(rolling: rolling), animated: true)
            }
            XCTAssertEqual(Set(view.effectiveSubviews.map(ObjectIdentifier.init)), before)
            XCTAssertNotNil(first.layer?.animation(forKey: "labSentinel"))
        }
    }

    func testSwitchAfterAnimatedRemovalClearsOutgoingSubviews() {
        for rolling in [false, true] {
            let view = DynamicCounterTextView(frame: .zero)
            view.update(value("11", count: "11", rolling: rolling), animated: false)
            view.update(value("22", count: "22", rolling: rolling), animated: true)
            XCTAssertGreaterThan(view.subviews.count, view.effectiveSubviews.count)
            view.update(value("", count: "", rolling: !rolling), animated: false)
            XCTAssertTrue(view.subviews.isEmpty)
            XCTAssertTrue(view.effectiveSubviews.isEmpty)
        }
    }

    func testModeSwitchReleasesOldViews() {
        weak var oldView: TextView?
        let view = DynamicCounterTextView(frame: .zero)
        autoreleasepool {
            view.update(value(), animated: false)
            oldView = view.effectiveSubviews.first
            view.update(value(rolling: true), animated: false)
        }
        XCTAssertNil(oldView)
    }

    func testAnimationsMatchOriginalAcrossDirectionsAndModes() throws {
        for rolling in [false, true] {
            for reversed in [false, true] {
                for fade in [false, true] {
                    for (first, second) in [("11", "12"), ("12", "11"), ("9", "10"), ("99", "100"), ("999999999999999999999", "111111111111111111111")] {
                        let actual = DynamicCounterTextView(frame: .zero)
                        let original = ReferenceDynamicCounterTextView(frame: .zero)
                        for (index, text) in [first, second].enumerated() {
                            actual.update(DynamicCounterTextView.make(for: text, count: text, font: .normal(13), textColor: .black, width: 300, onlyFade: fade, kerned: rolling, rolling: rolling), animated: index == 1, reversed: reversed)
                            original.update(ReferenceDynamicCounterTextView.make(for: text, count: text, font: .normal(13), textColor: .black, width: 300, onlyFade: fade, kerned: rolling, rolling: rolling), animated: index == 1, reversed: reversed)
                        }
                        XCTAssertEqual(animationSignatures(actual.subviews), animationSignatures(original.subviews), "\(first) to \(second), rolling \(rolling), reversed \(reversed), fade \(fade)")
                        XCTAssertEqual(try render(actual.effectiveSubviews), try render(original.effectiveSubviews))
                    }
                }
            }
        }
    }

    func testEqualRegularValueDoesNotInvalidateTextDrawing() {
        let view = DynamicCounterTextView(frame: .zero)
        view.update(value(), animated: false)
        for child in view.effectiveSubviews {
            child.drawingLayer.display()
            XCTAssertFalse(child.drawingLayer.needsDisplay())
        }
        view.update(value(), animated: true)
        XCTAssertTrue(view.effectiveSubviews.allSatisfy { !$0.drawingLayer.needsDisplay() })
    }

    func testUnneededLayoutForReusedPrefixIsReleased() {
        let view = DynamicCounterTextView(frame: .zero)
        view.update(value("Participants 11", count: "11"), animated: false)
        weak var unusedLayout: TextViewLayout?
        autoreleasepool {
            let next = value("Participants 12", count: "12")
            unusedLayout = next.values[0].0
            view.update(next, animated: false)
        }
        XCTAssertNil(unusedLayout)
    }

    func testChangedTimerRetainsOnlyTheLayoutItsNewDigitUses() {
        final class WeakLayout {
            weak var value: TextViewLayout?
            init(_ value: TextViewLayout) { self.value = value }
        }
        let view = DynamicCounterTextView(frame: .zero)
        view.update(value("00:58", count: "00:58"), animated: false)
        var prepared: [WeakLayout] = []
        autoreleasepool {
            let next = value("00:59", count: "00:59")
            prepared = next.values.map { WeakLayout($0.0) }
            view.update(next, animated: false)
        }
        XCTAssertEqual(prepared.count, 5)
        XCTAssertEqual(prepared.filter { $0.value == nil }.count, 4)
        XCTAssertNotNil(prepared.last?.value)
    }

    func testAnimatedGeometryChangesPreserveViewsAndUseCorrectOffsets() throws {
        for kerned in [false, true] {
            let view = DynamicCounterTextView(frame: .zero)
            view.update(value("Participants 12", count: "12"), animated: false)
            let oldOrigins = Dictionary(uniqueKeysWithValues: view.effectiveSubviews.map { (ObjectIdentifier($0), $0.frame.origin) })
            let next = value("Participants 12", count: "12", width: kerned ? 240 : 80, kerned: kerned)
            view.update(next, animated: true)
            try assertMatchesFresh(view, value: next)
            for child in view.effectiveSubviews {
                let old = try XCTUnwrap(oldOrigins[ObjectIdentifier(child)])
                if old != child.frame.origin {
                    let animation = try XCTUnwrap(child.layer?.animation(forKey: "position") as? CABasicAnimation)
                    XCTAssertTrue(animation.isAdditive)
                    XCTAssertEqual((animation.fromValue as? NSValue)?.pointValue, NSPoint(x: old.x - child.frame.minX, y: old.y - child.frame.minY))
                    XCTAssertEqual((animation.toValue as? NSValue)?.pointValue, .zero)
                }
            }
        }
    }

    func testStyleAndFadeChangesMatchFreshInBothModes() throws {
        for rolling in [false, true] {
            let view = DynamicCounterTextView(frame: .zero)
            for (font, color, fade) in [(NSFont.systemFont(ofSize: 13), NSColor.black, false), (NSFont.boldSystemFont(ofSize: 18), NSColor.white, true), (NSFont.systemFont(ofSize: 13), NSColor.red, false)] {
                let next = DynamicCounterTextView.make(for: "12 participants", count: "12", font: font, textColor: color, width: 240, onlyFade: fade, kerned: rolling, rolling: rolling)
                view.update(next, animated: false)
                try assertMatchesFresh(view, value: next)
            }
        }
    }

    func testLongRollingStyleChangesAndClearMatchFreshControl() throws {
        let view = DynamicCounterTextView(frame: .zero)
        let text = String(repeating: "1", count: 128)
        for color in [NSColor.black, .white, .red] {
            let next = DynamicCounterTextView.make(for: text, count: text, font: .normal(13), textColor: color, width: .greatestFiniteMagnitude, kerned: true, rolling: true)
            view.update(next, animated: false)
            XCTAssertEqual(view.effectiveSubviews.count, 128)
            try assertMatchesFresh(view, value: next)
        }
        view.update(value("", count: "", rolling: true), animated: false)
        XCTAssertTrue(view.effectiveSubviews.isEmpty)
        XCTAssertTrue(view.subviews.isEmpty)
    }

    func testRegularReconciliationHandlesPrefixSuffixAndMissingCount() throws {
        let view = DynamicCounterTextView(frame: .zero)
        for (text, count) in [("12 people", "12"), ("people 13", "13"), ("people 14 here", "14"), ("15", "missing"), ("count 16", ""), ("0", "0")] {
            let next = value(text, count: count)
            view.update(next, animated: false)
            try assertMatchesFresh(view, value: next)
        }
        view.update(value("", count: ""), animated: false)
        XCTAssertTrue(view.effectiveSubviews.isEmpty)
        XCTAssertTrue(view.subviews.isEmpty)
    }

    func testCounterInstanceAndDictionaryPayloadShrink() {
        XCTAssertLessThan(class_getInstanceSize(DynamicCounterTextView.self), class_getInstanceSize(ReferenceDynamicCounterTextView.self))
        XCTAssertLessThan(MemoryLayout<TextView>.stride, MemoryLayout<(TextView, ReferenceDynamicCounterTextView.Text)>.stride)
    }

    private func animationSignatures(_ subviews: [NSView]) -> [String] {
        subviews.compactMap { $0 as? TextView }.map { view in
            let animations = (view.layer?.animationKeys() ?? []).sorted().map { key -> String in
                let animation = view.layer!.animation(forKey: key) as! CABasicAnimation
                return "\(key):\(String(describing: animation.fromValue)):\(String(describing: animation.toValue)):\(animation.duration):\(animation.speed):\(animation.isAdditive):\(animation.isRemovedOnCompletion):\(animation.fillMode.rawValue)"
            }.joined(separator: ";")
            return "\(view.textLayout!.attributedString.string)|\(view.frame)|\(animations)"
        }.sorted()
    }

    func testUpdateBenchmark() throws {
        guard ProcessInfo.processInfo.environment["COUNTER_UPDATE_BENCHMARK"] != nil else { throw XCTSkip("Opt-in update benchmark") }
        var report: [String: Any] = [:]
        for rolling in [false, true] {
            for changed in [false, true] {
                let actual = DynamicCounterTextView(frame: .zero)
                let original = ReferenceDynamicCounterTextView(frame: .zero)
                let texts = changed ? ["00:58", "00:59"] : ["00:59", "00:59"]
                let values = texts.map { value($0, count: $0, kerned: rolling, rolling: rolling) }
                let originals = texts.map { ReferenceDynamicCounterTextView.make(for: $0, count: $0, font: .normal(13), textColor: .black, width: 240, kerned: rolling, rolling: rolling) }
                actual.update(values[0], animated: false)
                original.update(originals[0], animated: false)
                var before: [Double] = [], after: [Double] = []
                for batch in 0..<9 {
                    for candidate in batch % 2 == 0 ? [false, true] : [true, false] {
                        let elapsed = autoreleasepool { () -> Double in
                            let start = CACurrentMediaTime()
                            for index in 0..<1000 {
                                if candidate { actual.update(values[index % 2], animated: false) }
                                else { original.update(originals[index % 2], animated: false) }
                            }
                            return (CACurrentMediaTime() - start) * 1000
                        }
                        if candidate { after.append(elapsed) } else { before.append(elapsed) }
                    }
                }
                report["\(rolling ? "rolling" : "regular") \(changed ? "changed" : "equal")"] = ["original_ms_per_1000": before, "candidate_ms_per_1000": after]
            }
        }
        let originalInstance = ReferenceDynamicCounterTextView(frame: .zero)
        let candidateInstance = DynamicCounterTextView(frame: .zero)
        withExtendedLifetime((originalInstance, candidateInstance)) {
            report["memory"] = ["original_instance_bytes": class_getInstanceSize(ReferenceDynamicCounterTextView.self), "candidate_instance_bytes": class_getInstanceSize(DynamicCounterTextView.self), "original_dictionary_value_stride": MemoryLayout<(TextView, ReferenceDynamicCounterTextView.Text)>.stride, "candidate_dictionary_value_stride": MemoryLayout<TextView>.stride, "original_dictionary_key_stride": MemoryLayout<ReferenceDynamicCounterTextView.Text>.stride, "candidate_dictionary_key_stride": MemoryLayout<Int>.stride, "original_malloc_bytes": malloc_size(Unmanaged.passUnretained(originalInstance).toOpaque()), "candidate_malloc_bytes": malloc_size(Unmanaged.passUnretained(candidateInstance).toOpaque())]
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/counter-update-benchmark.json"))
    }

    func testLongCounterUpdateBenchmark() throws {
        guard ProcessInfo.processInfo.environment["COUNTER_UPDATE_BENCHMARK"] != nil else { throw XCTSkip("Opt-in long counter benchmark") }
        var report: [String: Any] = [:]
        for length in [32, 128] {
            let text = String(repeating: "1", count: length)
            for rolling in [false, true] {
                let actual = DynamicCounterTextView(frame: .zero)
                let original = ReferenceDynamicCounterTextView(frame: .zero)
                let values = (0..<2).map { _ in DynamicCounterTextView.make(for: text, count: text, font: .normal(13), textColor: .black, width: .greatestFiniteMagnitude, kerned: rolling, rolling: rolling) }
                let originals = (0..<2).map { _ in ReferenceDynamicCounterTextView.make(for: text, count: text, font: .normal(13), textColor: .black, width: .greatestFiniteMagnitude, kerned: rolling, rolling: rolling) }
                actual.update(values[0], animated: false)
                original.update(originals[0], animated: false)
                var before: [Double] = [], after: [Double] = []
                for batch in 0..<9 {
                    for candidate in batch % 2 == 0 ? [false, true] : [true, false] {
                        let elapsed = autoreleasepool { () -> Double in
                            let start = CACurrentMediaTime()
                            for index in 0..<1000 {
                                if candidate { actual.update(values[index % 2], animated: false) }
                                else { original.update(originals[index % 2], animated: false) }
                            }
                            return (CACurrentMediaTime() - start) * 1000
                        }
                        if candidate { after.append(elapsed) } else { before.append(elapsed) }
                    }
                }
                report["\(rolling ? "rolling" : "regular") \(length)"] = ["original_ms_per_1000": before, "candidate_ms_per_1000": after]
            }
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/counter-long-update-benchmark.json"))
    }

    func testLongChangedRegularBenchmark() throws {
        guard ProcessInfo.processInfo.environment["COUNTER_UPDATE_BENCHMARK"] != nil else { throw XCTSkip("Opt-in long changed counter benchmark") }
        var report: [String: Any] = [:]
        for length in [32, 128] {
            let texts = [String(repeating: "1", count: length), String(repeating: "2", count: length)]
            let actual = DynamicCounterTextView(frame: .zero)
            let original = ReferenceDynamicCounterTextView(frame: .zero)
            let values = texts.map { DynamicCounterTextView.make(for: $0, count: $0, font: .normal(13), textColor: .black, width: .greatestFiniteMagnitude) }
            let originals = texts.map { ReferenceDynamicCounterTextView.make(for: $0, count: $0, font: .normal(13), textColor: .black, width: .greatestFiniteMagnitude) }
            actual.update(values[0], animated: false)
            original.update(originals[0], animated: false)
            var before: [Double] = [], after: [Double] = []
            for batch in 0..<9 {
                for candidate in batch % 2 == 0 ? [false, true] : [true, false] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for index in 0..<50 {
                            if candidate { actual.update(values[index % 2], animated: false) }
                            else { original.update(originals[index % 2], animated: false) }
                        }
                        return (CACurrentMediaTime() - start) * 1000
                    }
                    if candidate { after.append(elapsed) } else { before.append(elapsed) }
                }
            }
            report[String(length)] = ["original_ms_per_50": before, "candidate_ms_per_50": after]
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/counter-long-changed-benchmark.json"))
    }

    private func render(_ views: [TextView]) throws -> Data {
        let width = 600, height = 100
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        for view in views.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            context.saveGState()
            context.translateBy(x: view.frame.minX, y: view.frame.minY)
            view.draw(view.drawingLayer, in: context)
            context.restoreGState()
        }
        let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        XCTAssertTrue(data.contains { $0 != 0 })
        return data
    }
}
