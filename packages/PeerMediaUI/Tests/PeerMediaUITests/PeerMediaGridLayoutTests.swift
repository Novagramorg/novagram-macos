import XCTest
import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import ChatHistoryModel
import MessageUtils
@testable import PeerMediaUI

final class PeerMediaGridLayoutTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1))
    private let day: Int32 = 24 * 60 * 60

    private func message(id: Int32, timestamp: Int32, namespace: Int32 = Namespaces.Message.Cloud) -> Message {
        return Message(stableId: UInt32(id), stableVersion: 0, id: MessageId(peerId: self.peerId, namespace: namespace, id: id), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: timestamp, flags: [], tags: [.photoOrVideo], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "", attributes: [], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func history(monthSizes: [Int], albumEvery: Int = 7) -> [Message] {
        var result: [Message] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 1
        var id: Int32 = 1
        for (monthIndex, size) in monthSizes.enumerated() {
            components.month = 1 + monthIndex
            let start = Int32(calendar.date(from: components)!.timeIntervalSince1970)
            let span = 25 * self.day
            var timestamp = start + 3600
            for index in 0 ..< size {
                result.append(self.message(id: id, timestamp: timestamp))
                id += 1
                if index % albumEvery != albumEvery - 1 {
                    timestamp += max(1, span / Int32(max(1, size)))
                }
            }
        }
        return result
    }

    private func window(_ history: [Message], lower: Int, upper: Int) -> (messages: [Message], bounds: PeerMediaGridBounds) {
        let lower = max(0, lower)
        let upper = min(history.count, upper)
        let messages = Array(history[lower ..< upper].reversed())
        let bounds = PeerMediaGridBounds(laterIndex: upper < history.count ? MessageIndex(history[upper]) : nil, earlierIndex: lower > 0 ? MessageIndex(history[lower - 1]) : nil, holeLater: false, holeEarlier: false)
        return (messages, bounds)
    }

    private func layout(_ window: (messages: [Message], bounds: PeerMediaGridBounds), perRow: Int, hint: PeerMediaGridHint?) -> [PeerMediaMonthEntry] {
        return peerMediaMonthEntries(messages: window.messages, perRowCount: perRow, timeDifference: 0, isExternalSearch: false, bounds: window.bounds, hint: hint)
    }

    private func rows(_ entries: [PeerMediaMonthEntry]) -> [[MessageId]] {
        return entries.compactMap { entry in
            if case let .line(_, _, items, _, _, _) = entry {
                return items.map { $0.id }
            }
            return nil
        }
    }

    private func months(_ entries: [PeerMediaMonthEntry]) -> [[[MessageId]]] {
        var result: [[[MessageId]]] = [[]]
        for entry in entries {
            switch entry {
            case .date, .section:
                result.append([])
            case let .line(_, _, items, _, _, _):
                result[result.count - 1].append(items.map { $0.id })
            }
        }
        return result.filter { !$0.isEmpty }
    }

    private func assertStrictlyOrdered(_ entries: [PeerMediaMonthEntry], file: StaticString = #filePath, line: UInt = #line) {
        for index in 1 ..< max(1, entries.count) {
            XCTAssertTrue(entries[index - 1] < entries[index], "entry \(index - 1) does not precede entry \(index)", file: file, line: line)
            XCTAssertFalse(entries[index] < entries[index - 1], "entry \(index) precedes entry \(index - 1)", file: file, line: line)
        }
        XCTAssertEqual(Set(entries.map { $0.stableId }).count, entries.count, "duplicate stable ids", file: file, line: line)
    }

    private func apply(_ left: [PeerMediaMonthEntry], _ right: [PeerMediaMonthEntry]) -> (result: [PeerMediaMonthEntry], deleted: [Int], inserted: [Int]) {
        let (deleted, inserted, updated) = mergeListsStableWithUpdates(leftList: left, rightList: right)
        var result = left
        for index in deleted.reversed() {
            result.remove(at: index)
        }
        for (index, entry, _) in inserted {
            result.insert(entry, at: index)
        }
        for (index, entry, _) in updated {
            result[index] = entry
        }
        return (result, deleted, inserted.map { $0.0 })
    }

    func testDisplayOrderOfExpandedMedia() {
        let original = MessageIndex(id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 10), timestamp: 100)
        let expanded = MessageIndex(id: MessageId(peerId: self.peerId, namespace: 0x0010_0001, id: 10), timestamp: 100)
        let expandedSecond = MessageIndex(id: MessageId(peerId: self.peerId, namespace: 0x0010_0002, id: 10), timestamp: 100)
        let older = MessageIndex(id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 9), timestamp: 100)
        let newer = MessageIndex(id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 11), timestamp: 101)
        let ordered = [newer, original, expanded, expandedSecond, older]
        for i in 0 ..< ordered.count {
            for j in 0 ..< ordered.count {
                XCTAssertEqual(sharedMediaDisplayPrecedes(ordered[i], ordered[j]), i < j, "\(i) vs \(j)")
            }
        }
    }

    func testEntriesFollowExpandedMediaOrder() {
        var messages: [Message] = []
        messages.append(self.message(id: 30, timestamp: 1_000_300))
        messages.append(self.message(id: 20, timestamp: 1_000_200))
        for index in 1 ... 5 {
            messages.append(self.message(id: 20, timestamp: 1_000_200, namespace: 0x0010_0000 + Int32(index)))
        }
        messages.append(self.message(id: 10, timestamp: 1_000_100))
        let entries = peerMediaMonthEntries(messages: messages, perRowCount: 3, timeDifference: 0, isExternalSearch: false, bounds: .complete, hint: nil)
        XCTAssertEqual(self.rows(entries).flatMap { $0 }, messages.map { $0.id })
        self.assertStrictlyOrdered(entries)
    }

    func testTopOfHistoryIsStartAligned() {
        let history = self.history(monthSizes: [5, 23, 1, 40, 12])
        for perRow in [3, 4, 6, 7] {
            let entries = self.layout(self.window(history, lower: 0, upper: history.count), perRow: perRow, hint: nil)
            self.assertStrictlyOrdered(entries)
            XCTAssertEqual(self.rows(entries).flatMap { $0 }, history.reversed().map { $0.id })
            for month in self.months(entries) {
                for row in month.dropLast() {
                    XCTAssertEqual(row.count, perRow)
                }
                XCTAssertLessThanOrEqual(month.last?.count ?? 0, perRow)
            }
        }
    }

    func testMonthHeadersSeparateMonths() {
        let history = self.history(monthSizes: [4, 9, 2])
        let entries = self.layout(self.window(history, lower: 0, upper: history.count), perRow: 4, hint: nil)
        var headers = 0
        var lineMonth: Int64?
        for entry in entries {
            switch entry {
            case .date:
                headers += 1
                lineMonth = nil
            case let .line(_, _, items, _, _, _):
                let months = Set(items.map { mediaDateId(for: $0.timestamp) })
                XCTAssertEqual(months.count, 1)
                if let lineMonth {
                    XCTAssertEqual(lineMonth, months.first)
                }
                lineMonth = months.first
            case .section:
                break
            }
        }
        XCTAssertEqual(headers, 2)
    }

    private func slide(history: [Message], perRow: Int, size: Int, steps: [Int], start: Int, file: StaticString = #filePath, line: UInt = #line) {
        var upper = start
        var previousWindow = self.window(history, lower: upper - size, upper: upper)
        var previous = self.layout(previousWindow, perRow: perRow, hint: nil)
        var hint = PeerMediaGridHint(perRowCount: perRow).recording(previous, perRowCount: perRow)
        for step in steps {
            upper = min(history.count, max(size / 2, upper + step))
            let currentWindow = self.window(history, lower: upper - size, upper: upper)
            let current = self.layout(currentWindow, perRow: perRow, hint: hint)
            self.assertStrictlyOrdered(current, file: file, line: line)
            XCTAssertEqual(self.rows(current).flatMap { $0 }, currentWindow.messages.map { $0.id }, file: file, line: line)

            let applied = self.apply(previous, current)
            XCTAssertEqual(applied.result.map { $0.stableId }, current.map { $0.stableId }, "diff does not reproduce the new list", file: file, line: line)

            let previousRows = Dictionary(self.rows(previous).map { ($0[0], $0) }, uniquingKeysWith: { lhs, _ in lhs })
            let currentRows = Dictionary(self.rows(current).map { ($0[0], $0) }, uniquingKeysWith: { lhs, _ in lhs })
            let kept = Set(previousRows.filter { currentRows[$0.key] == $0.value }.map { $0.key })
            let deletedKept = applied.deleted.filter { index in
                if case let .line(_, _, items, _, _, _) = previous[index] {
                    return kept.contains(items[0].id)
                }
                return false
            }
            XCTAssertTrue(deletedKept.isEmpty, "\(deletedKept.count) unchanged rows were deleted and reinserted (step \(step))", file: file, line: line)

            let shared = Set(previousWindow.messages.map { $0.id }).intersection(currentWindow.messages.map { $0.id })
            let previousMonths = self.months(previous)
            let currentMonths = self.months(current)
            func rowOf(_ months: [[[MessageId]]]) -> [MessageId: [MessageId]] {
                var result: [MessageId: [MessageId]] = [:]
                for (monthIndex, month) in months.enumerated() {
                    for (rowIndex, row) in month.enumerated() {
                        let isEdge = (monthIndex == 0 && rowIndex == 0) || (monthIndex == months.count - 1 && rowIndex == month.count - 1)
                        if isEdge {
                            continue
                        }
                        for id in row {
                            result[id] = row
                        }
                    }
                }
                return result
            }
            let previousRowOf = rowOf(previousMonths)
            let currentRowOf = rowOf(currentMonths)
            var moved = 0
            for id in shared {
                if let before = previousRowOf[id], let after = currentRowOf[id], before.count == perRow, after.count == perRow, before != after {
                    moved += 1
                }
            }
            XCTAssertEqual(moved, 0, "\(moved) messages changed rows inside full rows (step \(step))", file: file, line: line)

            previous = current
            previousWindow = currentWindow
            hint = hint.recording(current, perRowCount: perRow)
        }
    }

    func testScrollingDownAndUpKeepsRows() {
        let history = self.history(monthSizes: [120, 480, 75, 610, 33, 260])
        for perRow in [4, 6, 7] {
            let steps = Array(repeating: -137, count: 12) + Array(repeating: 211, count: 12)
            self.slide(history: history, perRow: perRow, size: 400, steps: steps, start: history.count)
        }
    }

    func testSmallStepsKeepRows() {
        let history = self.history(monthSizes: [700, 90, 900])
        let steps = Array(repeating: -31, count: 40) + Array(repeating: 29, count: 40)
        self.slide(history: history, perRow: 6, size: 300, steps: steps, start: history.count)
    }

    func testReturningToTopRestoresStartAlignment() {
        let history = self.history(monthSizes: [50, 500])
        let perRow = 6
        let full = self.layout(self.window(history, lower: history.count - 300, upper: history.count), perRow: perRow, hint: nil)
        var hint = PeerMediaGridHint(perRowCount: perRow).recording(full, perRowCount: perRow)
        var upper = history.count
        for _ in 0 ..< 5 {
            upper -= 97
            hint = hint.recording(self.layout(self.window(history, lower: upper - 300, upper: upper), perRow: perRow, hint: hint), perRowCount: perRow)
        }
        let back = self.layout(self.window(history, lower: history.count - 300, upper: history.count), perRow: perRow, hint: hint)
        XCTAssertEqual(self.rows(back), self.rows(full))
    }

    func testLargeMonthKeepsRowsWhenScrolledBackIntoIt() {
        let history = self.history(monthSizes: [40, 900, 60])
        let perRow = 6
        let size = 300
        let canonical = self.layout(self.window(history, lower: 0, upper: history.count), perRow: perRow, hint: nil)
        let canonicalRows = Dictionary(self.rows(canonical).filter { $0.count == perRow }.map { ($0[0], $0) }, uniquingKeysWith: { lhs, _ in lhs })
        var upper = history.count
        var hint = PeerMediaGridHint(perRowCount: perRow).recording(self.layout(self.window(history, lower: upper - size, upper: upper), perRow: perRow, hint: nil), perRowCount: perRow)
        var path: [Int] = []
        for _ in 0 ..< 14 {
            path.append(-73)
        }
        for _ in 0 ..< 14 {
            path.append(61)
        }
        for step in path {
            upper = min(history.count, max(size, upper + step))
            let entries = self.layout(self.window(history, lower: upper - size, upper: upper), perRow: perRow, hint: hint)
            hint = hint.recording(entries, perRowCount: perRow)
            let months = self.months(entries)
            for (monthIndex, month) in months.enumerated() {
                for (rowIndex, row) in month.enumerated() where row.count == perRow {
                    let isEdge = (monthIndex == 0 && rowIndex == 0) || (monthIndex == months.count - 1 && rowIndex == month.count - 1)
                    if !isEdge {
                        XCTAssertEqual(canonicalRows[row[0]], row, "row starting at \(row[0].id) differs from the top-of-history layout")
                    }
                }
            }
        }
    }

    private func columns(_ entries: [PeerMediaMonthEntry]) -> [MessageId: Int] {
        var result: [MessageId: Int] = [:]
        for entry in entries {
            if case let .line(_, _, items, _, _, gap) = entry {
                for (index, message) in items.enumerated() {
                    result[message.id] = gap + index
                }
            }
        }
        return result
    }

    func testTopEdgeRowKeepsColumnsWhileLoadingAbove() {
        let history = self.history(monthSizes: [30, 400, 30])
        let perRow = 6
        let canonical = self.columns(self.layout(self.window(history, lower: 0, upper: history.count), perRow: perRow, hint: nil))
        var upper = history.count
        var hint = PeerMediaGridHint(perRowCount: perRow).recording(self.layout(self.window(history, lower: upper - 200, upper: upper), perRow: perRow, hint: nil), perRowCount: perRow)
        for _ in 0 ..< 6 {
            upper -= 41
            hint = hint.recording(self.layout(self.window(history, lower: upper - 200, upper: upper), perRow: perRow, hint: hint), perRowCount: perRow)
        }
        for extra in 1 ... 7 {
            let entries = self.layout(self.window(history, lower: upper - 200, upper: upper + extra), perRow: perRow, hint: hint)
            for (id, column) in self.columns(entries) {
                XCTAssertEqual(column, canonical[id], "message \(id.id) sits in column \(column) instead of \(canonical[id] ?? -1)")
            }
            if case let .line(_, _, items, _, _, gap)? = entries.first {
                XCTAssertEqual(gap + items.count <= perRow, true)
            }
        }
    }

    func testNewestMessageReflowsAtTop() {
        let history = self.history(monthSizes: [30])
        let perRow = 4
        let before = self.layout(self.window(history, lower: 0, upper: history.count - 1), perRow: perRow, hint: nil)
        let after = self.layout(self.window(history, lower: 0, upper: history.count), perRow: perRow, hint: PeerMediaGridHint(perRowCount: perRow).recording(before, perRowCount: perRow))
        let canonical = self.layout(self.window(history, lower: 0, upper: history.count), perRow: perRow, hint: nil)
        XCTAssertEqual(self.rows(after), self.rows(canonical))
        XCTAssertEqual(self.rows(after).first?.count, perRow)
    }

    func testResizeIgnoresHint() {
        let history = self.history(monthSizes: [200])
        let window = self.window(history, lower: 20, upper: 150)
        let six = self.layout(window, perRow: 6, hint: nil)
        let four = self.layout(window, perRow: 4, hint: PeerMediaGridHint(perRowCount: 6).recording(six, perRowCount: 6))
        XCTAssertEqual(four.count, self.layout(window, perRow: 4, hint: nil).count)
        XCTAssertEqual(self.rows(four), self.rows(self.layout(window, perRow: 4, hint: nil)))
    }
}
