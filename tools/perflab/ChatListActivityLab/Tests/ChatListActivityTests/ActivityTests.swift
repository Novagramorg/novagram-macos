import Cocoa
import XCTest
import TGUIKit
@testable import ActivityText

final class ActivityTests: XCTestCase {
    typealias Input = (PeerId, [(Peer, PeerInputActivity)])
    private static var images: [NSImage] = []
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        theme = LabTheme()
        if Self.images.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
                image.setName(name); Self.images.append(image)
            }
        }
    }
    override func tearDown() { System.updateScaleFactor(2); theme = LabTheme() }
    private func input(_ name: String = "A very long peer name for activity truncation", namespace: Int32 = 2, activity: PeerInputActivity = .typingText, count: Int = 1) -> Input {
        (PeerId(namespace: namespace), (0..<count).map { (TestPeer(name + String($0)), activity) })
    }
    private func set(_ row: RowEnvironment, _ value: Input?) {
        if let row = row as? CurrentRow { row.inputActivities = value }
        if let row = row as? ReferenceRow { row.inputActivities = value }
    }
    private func get(_ row: RowEnvironment) -> Input? {
        if let row = row as? CurrentRow { return row.inputActivities }
        return (row as! ReferenceRow).inputActivities
    }
    private func bind(_ row: RowEnvironment, _ value: Input, width: CGFloat = 300) {
        row.item = ChatListRowItem(width: width, activities: value.1)
        set(row, get(row))
        set(row, value)
    }
    private func pixels(_ layout: TextViewLayout) -> Data {
        let context = CGContext(data: nil, width: 1200, height: 150, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: System.backingScale, y: System.backingScale)
        for line in layout.lines { context.textPosition = CGPoint(x: 5 + line.frame.minX, y: 30); CTLineDraw(line.line, context) }
        return Data(bytes: context.data!, count: 720000)
    }
    private func assertFresh(_ row: CurrentRow, _ value: Input, file: StaticString = #filePath, line: UInt = #line) {
        let reference = ChatActivitiesModel()
        reference.update(with: value, for: (row.item as! ChatListRowItem).inputActivityWidth, theme: row.activitiesModel!.theme!) { _ in }
        let expected = reference.view!.subviews.compactMap { $0 as? TextView }.first!.textLayout!
        let actual = row.textLayout!
        XCTAssertEqual(actual.attributedString, expected.attributedString, file: file, line: line)
        XCTAssertEqual(actual.layoutSize, expected.layoutSize, file: file, line: line)
        XCTAssertEqual(actual.lines.map(\.range), expected.lines.map(\.range), file: file, line: line)
        let referencePixels = pixels(expected)
        XCTAssertTrue(referencePixels.contains { $0 != 0 }, file: file, line: line)
        XCTAssertEqual(pixels(actual), referencePixels, file: file, line: line)
    }
    func testResizeReproducesOriginalStaleTruncationAndRefreshesCandidate() {
        let old = ReferenceRow(), new = CurrentRow(), value = input()
        bind(old, value, width: 400); bind(new, value, width: 400)
        for width in [CGFloat(80), 230, 400, 120] {
            (old.item as! ChatListRowItem).inputActivityWidth = width
            (new.item as! ChatListRowItem).inputActivityWidth = width
            set(old, value); set(new, value)
            XCTAssertEqual(old.textLayout!.constrainedWidth, 370)
            XCTAssertEqual(new.textLayout!.constrainedWidth, width - 30)
            assertFresh(new, value)
        }
    }
    func testChangingConversationNamespaceRefreshesActivityWording() {
        let old = ReferenceRow(), new = CurrentRow()
        let first = input(namespace: 0), second = (PeerId(namespace: 2), first.1)
        bind(old, first); bind(new, first)
        let original = old.textLayout!.string
        set(old, second); set(new, second)
        XCTAssertEqual(old.textLayout!.string, original)
        XCTAssertNotEqual(new.textLayout!.string, original)
        assertFresh(new, second)
    }
    func testIncomingValueIsComparedRatherThanItemSnapshot() {
        let old = ReferenceRow(), new = CurrentRow(), first = input("Ada"), second = input("Grace")
        bind(old, first); bind(new, first)
        set(old, second); set(new, second)
        XCTAssertTrue(old.textLayout!.string.contains("Ada"))
        XCTAssertTrue(new.textLayout!.string.contains("Grace"))
        assertFresh(new, second)
    }
    func testBindingNewItemAvoidsRedundantOldActivityUpdate() {
        let old = ReferenceRow(), new = CurrentRow()
        bind(old, input("Ada")); bind(new, input("Ada"))
        let oldCount = old.activitiesModel!.updates, newCount = new.activitiesModel!.updates
        bind(old, input("Grace")); bind(new, input("Grace"))
        XCTAssertEqual(old.activitiesModel!.updates - oldCount, 2)
        XCTAssertEqual(new.activitiesModel!.updates - newCount, 1)
        XCTAssertEqual(old.textLayout!.attributedString, new.textLayout!.attributedString)
    }
    func testScaleThemeSelectionAndWidthInvalidateExactlyOnce() {
        let new = CurrentRow(), value = input()
        bind(new, value)
        var count = new.activitiesModel!.updates
        for step in 0..<4 {
            switch step {
            case 0: System.updateScaleFactor(3)
            case 1: new.highlighed = true
            case 2: theme.chatList.activitySelectedColor = .green
            default: (new.item as! ChatListRowItem).inputActivityWidth = 90
            }
            set(new, value); count += 1
            XCTAssertEqual(new.activitiesModel!.updates, count)
            assertFresh(new, value)
            set(new, value)
            XCTAssertEqual(new.activitiesModel!.updates, count)
        }
    }
    func testAllActivitiesGroupsUnicodeAndSizesMatchFreshModel() {
        let new = CurrentRow()
        let activities: [PeerInputActivity] = [.typingText, .recordingVoice, .recordingInstantVideo, .uploadingFile(progress: 10), .uploadingPhoto(progress: 20), .uploadingVideo(progress: 30), .uploadingInstantVideo(progress: 40), .choosingSticker, .playingGame, .speakingInGroupCall(timestamp: 50), .seeingEmojiInteraction(emoticon: "🦆"), .interactingWithEmoji(emoticon: "🦆", messageId: MessageId(id: 1), interaction: nil)]
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for activity in activities {
                for count in 1...3 {
                    for width in [CGFloat(80), 200, 400] {
                        let value = input("مرحبا café 👨‍👩‍👧‍👦 ", activity: activity, count: count)
                        bind(new, value, width: width)
                        assertFresh(new, value)
                    }
                }
            }
        }
    }
    func testEqualReplacementPeersAndRepeatedBindingsSkipModelWork() {
        let new = CurrentRow()
        bind(new, input("Ada", count: 8))
        let count = new.activitiesModel!.updates
        for _ in 0..<1000 { set(new, input("Ada", count: 8)) }
        XCTAssertEqual(new.activitiesModel!.updates, count)
        set(new, input("Ada", count: 7))
        XCTAssertEqual(new.activitiesModel!.updates, count + 1)
        set(new, input("Ada", activity: .recordingVoice, count: 7))
        XCTAssertEqual(new.activitiesModel!.updates, count + 2)
    }
    func testEmptyNilInvalidItemAndPreviewsResetState() {
        let new = CurrentRow(), value = input()
        new.currentMediaPreviewSpecs = [(TestMessage(id: 1), 0, 0)]
        new.mediaPreviewViews = [1: NSView()]
        for mode in 0..<3 {
            bind(new, value)
            XCTAssertTrue(new.mediaPreviewViews[1]!.isHidden)
            weak var model = new.activitiesModel
            if mode == 0 { set(new, nil) }
            if mode == 1 { set(new, (value.0, [])) }
            if mode == 2 { new.item = NSObject(); set(new, value) }
            XCTAssertNil(new.activitiesModel)
            XCTAssertNil(model)
            XCTAssertFalse(new.hiddenMessage)
            XCTAssertTrue(new.contentView.subviews.isEmpty)
            XCTAssertEqual(new.mediaPreviewViews[1]!.isHidden, mode == 2)
            bind(new, value)
            XCTAssertEqual(new.activitiesModel!.updates, 1)
        }
    }
    func testReentrantHiddenMessageUpdateDoesNotRepeatModelUpdate() {
        let new = CurrentRow(), value = input()
        new.onHiddenChange = { [weak new] in
            guard let new else { return }
            let current = new.inputActivities
            new.inputActivities = current
        }
        bind(new, value)
        XCTAssertEqual(new.activitiesModel!.updates, 1)
        XCTAssertTrue(new.hiddenMessage)
        set(new, nil)
        XCTAssertNil(new.activitiesModel)
        XCTAssertFalse(new.hiddenMessage)
    }
    func testReentrantReplacementKeepsNewestTextAndWidth() {
        let new = CurrentRow(), first = input("Ada"), second = input("Grace")
        new.item = ChatListRowItem(width: 300, activities: first.1)
        new.onHiddenChange = { [weak new] in
            guard let new, new.hiddenMessage else { return }
            new.item = ChatListRowItem(width: 80, activities: second.1)
            new.inputActivities = second
        }
        set(new, first)
        XCTAssertEqual(new.activitiesModel!.updates, 2)
        assertFresh(new, second)
        set(new, second)
        XCTAssertEqual(new.activitiesModel!.updates, 2)
    }
    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["LIST_ACTIVITY_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        for scenario in ["same_1", "same_8", "same_64", "changed_binding", "empty"] {
            for pass in 0..<5 {
                func run(_ current: Bool) -> (Double, Int) {
                    let row: RowEnvironment = current ? CurrentRow() : ReferenceRow()
                    let count = scenario == "same_64" ? 64 : scenario == "same_8" ? 8 : 1
                    let first = input("Ada", count: count), second = input("Grace", count: count)
                    bind(row, first)
                    let start = CFAbsoluteTimeGetCurrent()
                    for i in 0..<10000 {
                        autoreleasepool {
                            if scenario == "changed_binding" { bind(row, i % 2 == 0 ? second : first) }
                            else { set(row, scenario == "empty" ? nil : first) }
                        }
                    }
                    return ((CFAbsoluteTimeGetCurrent() - start) * 100, row.activitiesModel?.updates ?? 0)
                }
                let old: (Double, Int), new: (Double, Int)
                if pass % 2 == 0 { old = run(false); new = run(true) } else { new = run(true); old = run(false) }
                print("BENCH \(scenario) pass=\(pass) baseline_us=\(old.0) current_us=\(new.0) baseline_updates=\(old.1) current_updates=\(new.1)")
            }
        }
    }
}
