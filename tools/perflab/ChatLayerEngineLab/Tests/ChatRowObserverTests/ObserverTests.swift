import Cocoa
import XCTest
import TGUIKit
@testable import ChatRowObserverHarness

private final class ComparisonObserver: Notifable {
    var comparisons = 0
    func notify(with value: Any, oldValue: Any, animated: Bool) {}
    func isEqual(to other: Notifable) -> Bool {
        comparisons += 1
        return self === other
    }
}

final class ObserverTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    func testRepeatedBindingsKeepOneRegistrationWithoutScanningOtherRows() {
        for make in [{ BaselineRow() as RowEnvironment }, { CandidateRow() as RowEnvironment }] {
            let interaction = ChatInteraction(), probe = ComparisonObserver()
            interaction.add(observer: probe)
            let rows = (0..<100).map { _ in make() }
            for (id, row) in rows.enumerated() { row.set(item: ChatRowItem(interaction, id: id)) }
            probe.comparisons = 0
            for _ in 0..<5 {
                for (id, row) in rows.enumerated() { row.set(item: ChatRowItem(interaction, id: id + 100)) }
            }
            if rows[0] is CandidateRow { XCTAssertEqual(probe.comparisons, 0) }
            else { XCTAssertEqual(probe.comparisons, 1000) }
            interaction.select([101])
            for (id, row) in rows.enumerated() { XCTAssertEqual(row.receivedIds, [id + 100]) }
        }
    }

    func testChangingInteractionsAndInvalidItemsRemoveOldMembership() {
        for make in [{ BaselineRow() as RowEnvironment }, { CandidateRow() as RowEnvironment }] {
            let a = ChatInteraction(), b = ChatInteraction(), row = make()
            row.set(item: ChatRowItem(a, id: 1))
            a.select([1])
            row.set(item: ChatRowItem(b, id: 2))
            a.select(nil); b.select([2])
            row.set(item: TableRowItem())
            a.select([1]); b.select(nil)
            XCTAssertEqual(row.receivedIds, [1, 2])
            row.set(item: ChatRowItem(a, id: 3))
            a.select(nil)
            XCTAssertEqual(row.receivedIds, [1, 2, 3])
        }
    }

    func testWindowAttachmentDetachAndDetachedBindingMatchOriginal() {
        for make in [{ BaselineRow() as RowEnvironment }, { CandidateRow() as RowEnvironment }] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let parent = NSView(), row = make(), interaction = ChatInteraction()
            window.contentView = parent
            row.set(item: ChatRowItem(interaction, id: 1))
            interaction.select([1])
            parent.addSubview(row)
            interaction.select(nil)
            row.removeFromSuperview()
            interaction.select([1])
            XCTAssertEqual(row.receivedIds, [1, 1])
            row.set(item: ChatRowItem(interaction, id: 2))
            interaction.select(nil)
            XCTAssertEqual(row.receivedIds, [1, 1, 2])
            parent.addSubview(row)
            for _ in 0..<10 { row.viewDidMoveToWindow() }
            interaction.select([2])
            XCTAssertEqual(row.receivedIds, [1, 1, 2, 2])
            row.removeFromSuperview()
            interaction.select(nil)
            XCTAssertEqual(row.receivedIds.count, 4)
        }
    }

    func testNotificationTimingDuringBindingMatchesOriginal() {
        for make in [{ BaselineRow() as RowEnvironment }, { CandidateRow() as RowEnvironment }] {
            let interaction = ChatInteraction(), row = make()
            row.set(item: ChatRowItem(interaction, id: 1))
            row.onSuperBind = { interaction.select([1]) }
            row.onRender = { interaction.select(nil) }
            row.onFill = { interaction.select([2]) }
            row.set(item: ChatRowItem(interaction, id: 2))
            XCTAssertEqual(row.receivedIds, [2, 2])
            row.onSuperBind = nil; row.onRender = nil; row.onFill = nil
            interaction.select(nil)
            XCTAssertEqual(row.receivedIds, [2, 2, 2])
        }
    }

    func testChatSwitchDoesNotDeliverOldOrPrematureNewNotifications() {
        for make in [{ BaselineRow() as RowEnvironment }, { CandidateRow() as RowEnvironment }] {
            let a = ChatInteraction(), b = ChatInteraction(), row = make()
            row.set(item: ChatRowItem(a, id: 1))
            row.onRender = { a.select([1]); b.select([2]) }
            row.onFill = { b.select(nil) }
            row.set(item: ChatRowItem(b, id: 2))
            XCTAssertEqual(row.receivedIds, [2])
            a.select(nil)
            XCTAssertEqual(row.receivedIds, [2])
            row.onRender = nil; row.onFill = nil
        }
    }

    func testNestedBindingRestoresNotificationsWhenInnerBindingFinishes() {
        for make in [{ BaselineRow() as RowEnvironment }, { CandidateRow() as RowEnvironment }] {
            let interaction = ChatInteraction(), row = make()
            row.set(item: ChatRowItem(interaction, id: 1))
            row.onRender = { [unowned row] in
                row.onRender = nil
                row.set(item: ChatRowItem(interaction, id: 3))
                interaction.select([3])
            }
            row.set(item: ChatRowItem(interaction, id: 2))
            XCTAssertEqual(row.receivedIds, [3])
            interaction.select(nil)
            XCTAssertEqual(row.receivedIds, [3, 3])
        }
    }

    func testWindowAttachmentDuringPreparationRestoresNotifications() {
        for make in [{ BaselineRow() as RowEnvironment }, { CandidateRow() as RowEnvironment }] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let parent = NSView(), row = make(), interaction = ChatInteraction()
            window.contentView = parent
            row.set(item: ChatRowItem(interaction, id: 1))
            row.onRender = { [unowned row] in
                parent.addSubview(row)
                interaction.select([2])
            }
            row.set(item: ChatRowItem(interaction, id: 2))
            XCTAssertEqual(row.receivedIds, [2])
            row.onRender = nil
            row.removeFromSuperview()
        }
    }

    func testRegistrationDoesNotRetainRowsOrPreviousInteractions() {
        let interaction = ChatInteraction()
        weak var released: CandidateRow?
        autoreleasepool {
            let row = CandidateRow()
            row.set(item: ChatRowItem(interaction, id: 1))
            released = row
        }
        XCTAssertNil(released)
        interaction.select([1])
        let row = CandidateRow()
        weak var releasedInteraction: ChatInteraction?
        autoreleasepool {
            let previous = ChatInteraction()
            row.set(item: ChatRowItem(previous, id: 2))
            releasedInteraction = previous
            row.set(item: ChatRowItem(interaction, id: 3))
        }
        XCTAssertNil(releasedInteraction)
        interaction.select(nil)
        XCTAssertEqual(row.receivedIds, [3])
    }

    func testMixedLifecycleSequenceMatchesOriginalForEveryRow() {
        let oldInteraction = [ChatInteraction(), ChatInteraction()]
        let newInteraction = [ChatInteraction(), ChatInteraction()]
        let oldRows = (0..<20).map { _ in BaselineRow() }, newRows = (0..<20).map { _ in CandidateRow() }
        for step in 0..<400 {
            let index = (step * 17) % 20
            let chat = (step / 13) % 2
            if step % 7 == 0 {
                oldRows[index].set(item: TableRowItem()); newRows[index].set(item: TableRowItem())
            } else if step % 11 == 0 {
                oldRows[index].viewDidMoveToWindow(); newRows[index].viewDidMoveToWindow()
            } else {
                oldRows[index].set(item: ChatRowItem(oldInteraction[chat], id: step))
                newRows[index].set(item: ChatRowItem(newInteraction[chat], id: step))
            }
            oldInteraction[chat].select(step % 3 == 0 ? nil : [step])
            newInteraction[chat].select(step % 3 == 0 ? nil : [step])
            for i in 0..<20 {
                XCTAssertEqual(newRows[i].receivedIds, oldRows[i].receivedIds, "step=\(step), row=\(i)")
                XCTAssertEqual(newRows[i].layoutCount, oldRows[i].layoutCount)
            }
        }
    }

    func testRebindBenchmark() throws {
        guard ProcessInfo.processInfo.environment["CHAT_OBSERVER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in observer binding benchmark") }
        var results: [String: [[Double]]] = [:]
        for switchesChat in [false, true] {
            for count in [1, 30, 100, 500] {
                let oldInteractions = [ChatInteraction(), ChatInteraction()], newInteractions = [ChatInteraction(), ChatInteraction()]
                let oldRows = (0..<count).map { _ in BaselineRow() }, newRows = (0..<count).map { _ in CandidateRow() }
                let oldItems = (0..<2).map { pass in (0..<count).map { ChatRowItem(oldInteractions[switchesChat ? pass : 0], id: $0 + pass * count) } }
                let newItems = (0..<2).map { pass in (0..<count).map { ChatRowItem(newInteractions[switchesChat ? pass : 0], id: $0 + pass * count) } }
                for i in 0..<count { oldRows[i].set(item: oldItems[0][i]); newRows[i].set(item: newItems[0][i]) }
                var samples = [[Double](), [Double]()]
                for batch in 0..<9 {
                    for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                        let start = CFAbsoluteTimeGetCurrent()
                        autoreleasepool {
                            for i in 0..<4000 {
                                let index = i % count, pass = (i / count) % 2
                                if variant == 0 { oldRows[index].set(item: oldItems[pass][index]) }
                                else { newRows[index].set(item: newItems[pass][index]) }
                            }
                        }
                        samples[variant].append((CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / 4000)
                    }
                }
                for interaction in oldInteractions + newInteractions { interaction.select([0]) }
                XCTAssertTrue(oldRows.allSatisfy { $0.receivedIds.count == 1 })
                XCTAssertTrue(newRows.allSatisfy { $0.receivedIds.count == 1 })
                results["\(switchesChat ? "switch" : "rebind")_\(count)_observers"] = samples
            }
        }
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_row_rebind", "batches_baseline_then_candidate": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-row-observer-benchmark.json"))
    }
}
