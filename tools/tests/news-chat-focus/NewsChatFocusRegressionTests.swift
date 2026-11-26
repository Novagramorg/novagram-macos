typealias MessageId = Int
typealias TableScrollFocus = Focus

struct MessageIndex: Comparable {
    let value: Int
    var id: Int { value }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}
struct Message { let id: Int }
struct Entry {
    let message: Message
    var index: MessageIndex { MessageIndex(value: message.id) }
}
enum MessageHistoryAnchorIndex: Equatable {
    case message(MessageIndex)
    func isLessOrEqual(to index: MessageIndex) -> Bool {
        switch self { case let .message(anchor): return anchor <= index }
    }
}
struct MessageHistoryView {
    var entries: [Entry]
    var anchorIndex = MessageHistoryAnchorIndex.message(MessageIndex(value: 50))
    var isAnchorOnlyWhileLoading = false
    var isLoading = false
    var holeEarlier = false
    var holeLater = false
    var topTaggedMessages: [Message] = []
}
enum ViewUpdateType: Equatable { case Generic, FillHole, UpdateVisible }
enum ChatHistoryViewUpdateType: Equatable {
    case Initial(fadeIn: Bool)
    case Generic(type: ViewUpdateType)
}
enum ChatHistoryInitialSearchLocation {
    case id(Int, String?, NSRange?)
    case index(MessageIndex, String?, NSRange?)
}
struct Focus {
    let focus: Bool
    var string: String? = nil
    var range: NSRange? = nil
}
enum TableScrollState {
    enum Side { case lower }
    case center(id: Int, innerId: Int?, animated: Bool, focus: Focus, inset: Int)
    case top(id: Int, innerId: Int?, animated: Bool, focus: Focus, inset: Int)
    case saveVisible(Side, Bool)
    case none(Int?)
}
enum ChatHistoryViewScrollPosition {
    enum Direction { case Down }
    case index(index: MessageHistoryAnchorIndex, position: TableScrollState, directionHint: Direction, animated: Bool)
    case keepInPlace(messageId: MessageId)
    case scroll(TableScrollState)
}
enum ChatHistoryEntryId {
    static func message(_ message: Message) -> Int { message.id }
}
struct ChatHistoryCombinedInitialData {
    let initialData: Int?
    let buttonKeyboardMessage: Message?
    let cachedData: Int
    let cachedDataMessages: Int
    let readStateData: Int
    let limitsConfiguration: Int
    let autoplayMedia: Int
    let autodownloadSettings: Int
}
func extractAdditionalData(view: MessageHistoryView, chatLocation: Int) -> (Int, Int, Int, Int, Int, Int) { (0, 0, 0, 0, 0, 0) }
enum ChatHistoryViewUpdate {
    case Loading(initialData: ChatHistoryCombinedInitialData, type: ChatHistoryViewUpdateType)
    case HistoryView(view: MessageHistoryView, type: ChatHistoryViewUpdateType, scrollPosition: ChatHistoryViewScrollPosition?, initialData: ChatHistoryCombinedInitialData)
}

final class NewsChatFocusRegressionTests: XCTestCase {
    func testScrollKeepsFocusUntilLoadingHistoryIsReady() {
        let pipe = ValuePipe<(MessageHistoryView, ViewUpdateType, Int?)>()
        var outputs: [ChatHistoryViewUpdate] = []
        let disposable = scrollUpdates(signal: pipe.signal()).start(next: { outputs.append($0) })
        defer { disposable.dispose() }
        var loading = view([])
        loading.isLoading = true
        pipe.putNext((loading, .Generic, nil))
        guard case .Loading? = outputs.last else { return XCTFail("Loading must not consume focus") }
        pipe.putNext((view([40, 50, 60]), .Generic, nil))
        guard case .HistoryView(_, _, .index(_, .center(50, _, _, _, _), _, _), _)? = outputs.last else { return XCTFail("Loaded target must receive the pending focus") }
        pipe.putNext((view([30, 40, 50, 60]), .Generic, nil))
        guard case .HistoryView(_, _, nil, _)? = outputs.last else { return XCTFail("Focus must only be applied once") }
    }

    func testScrollWaitsForEmptyHistoryHoleEvenWithoutLoadingFlag() {
        let pipe = ValuePipe<(MessageHistoryView, ViewUpdateType, Int?)>()
        var output: ChatHistoryViewUpdate?
        let disposable = scrollUpdates(signal: pipe.signal()).start(next: { output = $0 })
        defer { disposable.dispose() }
        var hole = view([])
        hole.holeEarlier = true
        pipe.putNext((hole, .Generic, nil))
        guard case .Loading? = output else { return XCTFail("A history hole is not a resolved target") }
        pipe.putNext((view([50]), .Generic, nil))
        guard case .HistoryView(_, _, .index?, _)? = output else { return XCTFail("Hole fill must retain focus") }
    }

    func testScrollWithLoadedTargetDoesNotWaitForUnrelatedHoles() {
        var loaded = view([40, 50, 60])
        loaded.holeEarlier = true
        var output: ChatHistoryViewUpdate?
        let disposable = scrollUpdates(signal: .single((loaded, .Generic, nil))).start(next: { output = $0 })
        defer { disposable.dispose() }
        guard case .HistoryView(_, _, .index?, _)? = output else { return XCTFail("A loaded scroll window must remain immediate") }
    }

    private func view(_ ids: [Int], partial: Bool = false) -> MessageHistoryView {
        MessageHistoryView(entries: ids.map { Entry(message: Message(id: $0)) }, isAnchorOnlyWhileLoading: partial, isLoading: partial)
    }

    private func assertCentered(_ update: ChatHistoryViewUpdate?, highlighted: Bool, expectedId: Int? = nil, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .HistoryView(_, _, .index(anchor, .center(id, _, animated, focus, _), _, _), _)? = update else {
            XCTFail("Expected explicit message-centered positioning", file: file, line: line)
            return
        }
        XCTAssertEqual(anchor, .message(MessageIndex(value: 50)), file: file, line: line)
        XCTAssertEqual(focus.focus, highlighted, file: file, line: line)
        XCTAssertFalse(animated, file: file, line: line)
        if let expectedId { XCTAssertEqual(id, expectedId, file: file, line: line) }
    }

    func testCachedPostIsCenteredImmediatelyWithoutWaitingForHistory() {
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: .single((view([50], partial: true), .Generic, nil)), cachedAnchor: true, searchLocation: .id(50, nil, nil)).start(next: { output = $0 })
        defer { disposable.dispose() }
        assertCentered(output, highlighted: true)
    }

    func testFullHistoryPreservesTappedPostWithoutRecentering() {
        let pipe = ValuePipe<(MessageHistoryView, ViewUpdateType, Int?)>()
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: pipe.signal(), cachedAnchor: true, searchLocation: .id(50, nil, nil)).start(next: { output = $0 })
        defer { disposable.dispose() }
        pipe.putNext((view([50], partial: true), .Generic, nil))
        pipe.putNext((view([40, 50, 60]), .FillHole, nil))
        guard case let .HistoryView(_, type, .keepInPlace(messageId), _)? = output else { return XCTFail("Expected anchor preservation") }
        XCTAssertEqual(messageId, 50)
        XCTAssertEqual(type, .Generic(type: .Generic))
    }

    func testAlreadyLoadedNewsMessageStillHighlights() {
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: .single((view([40, 50, 60]), .Generic, nil)), cachedAnchor: true, searchLocation: .id(50, nil, nil)).start(next: { output = $0 })
        defer { disposable.dispose() }
        assertCentered(output, highlighted: true, expectedId: 50)
    }

    func testLaterUpdatesDoNotKeepPullingUserBackToMessage() {
        let pipe = ValuePipe<(MessageHistoryView, ViewUpdateType, Int?)>()
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: pipe.signal(), cachedAnchor: true, searchLocation: .id(50, nil, nil)).start(next: { output = $0 })
        defer { disposable.dispose() }
        pipe.putNext((view([50], partial: true), .Generic, nil))
        pipe.putNext((view([40, 50, 60]), .FillHole, nil))
        pipe.putNext((view([30, 40, 50, 60, 70]), .Generic, nil))
        guard case .HistoryView(_, _, nil, _)? = output else { return XCTFail("Later history update must not reposition") }
    }

    func testPartialEditsDoNotRepeatedlyReposition() {
        let pipe = ValuePipe<(MessageHistoryView, ViewUpdateType, Int?)>()
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: pipe.signal(), cachedAnchor: true, searchLocation: .id(50, nil, nil)).start(next: { output = $0 })
        defer { disposable.dispose() }
        pipe.putNext((view([50], partial: true), .Generic, nil))
        pipe.putNext((view([50], partial: true), .FillHole, nil))
        guard case .HistoryView(_, .Generic(type: .Generic), nil, _)? = output else { return XCTFail("Partial edit must preserve current position") }
    }

    func testMissingTargetDoesNotHighlightNeighbor() {
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: .single((view([40, 60]), .Generic, nil)), cachedAnchor: true, searchLocation: .id(50, nil, nil)).start(next: { output = $0 })
        defer { disposable.dispose() }
        assertCentered(output, highlighted: false, expectedId: 60)
    }

    func testDeletedCachedPostIsRemovedWithoutFocusingAnotherMessage() {
        let pipe = ValuePipe<(MessageHistoryView, ViewUpdateType, Int?)>()
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: pipe.signal(), cachedAnchor: true, searchLocation: .id(50, nil, nil)).start(next: { output = $0 })
        defer { disposable.dispose() }
        pipe.putNext((view([50], partial: true), .Generic, nil))
        var deleted = view([])
        deleted.isLoading = true
        pipe.putNext((deleted, .FillHole, nil))
        guard case let .HistoryView(view, .Generic(type: .Generic), nil, _)? = output else { return XCTFail() }
        XCTAssertTrue(view.entries.isEmpty)
    }

    func testNormalMessageSearchKeepsQuoteAndFocus() {
        let range = NSRange(location: 2, length: 4)
        var output: ChatHistoryViewUpdate?
        let disposable = initialSearchUpdates(signal: .single((view([40, 50, 60]), .Generic, nil)), cachedAnchor: false, searchLocation: .id(50, "text", range)).start(next: { output = $0 })
        defer { disposable.dispose() }
        assertCentered(output, highlighted: true, expectedId: 50)
        guard case let .HistoryView(_, _, .index(_, .center(_, _, _, focus, _), _, _), _)? = output else { return XCTFail() }
        XCTAssertEqual(focus.string, "text")
        XCTAssertEqual(focus.range, range)
    }
}
