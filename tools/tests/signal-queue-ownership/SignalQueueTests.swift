import Foundation
import XCTest
import SwiftSignalKit

enum Failure { case generic }
final class Pending {
    var subscriber: Subscriber<Int,Failure>?
    var cancelled = false
    var starts = 0
    var onStart: (() -> Void)?
    var signal: Signal<Int,Failure> {
        Signal { subscriber in
            self.starts += 1; self.subscriber = subscriber; self.onStart?()
            return ActionDisposable { self.cancelled = true; self.subscriber = nil }
        }
    }
    func send(_ value: Int) { subscriber?.putNext(value) }
    func finish() { subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.generic) }
}
final class SignalQueueTests: XCTestCase {
    func testQueueReentrantNextSurvivesSynchronousHeadCompletion() {
        let pipe = ValuePipe<Signal<Int,Failure>>(); let next = Pending(); var values: [Int] = []
        let operation = (pipe.signal() |> castError(Failure.self) |> queue).start(next: { value in values.append(value); if value == 1 { pipe.putNext(next.signal) } })
        pipe.putNext(.single(1)); XCTAssertEqual(next.starts,1); XCTAssertFalse(next.cancelled); next.send(2); XCTAssertEqual(values,[1,2]); operation.dispose(); XCTAssertTrue(next.cancelled)
    }
    func testSwitchReentrantLatestIsNotCancelledByOldStartReturn() {
        let pipe = ValuePipe<Signal<Int,Failure>>(); let latest = Pending(); var values: [Int] = []
        let operation = (pipe.signal() |> castError(Failure.self) |> switchToLatest).start(next: { value in values.append(value); if value == 1 { pipe.putNext(latest.signal) } })
        pipe.putNext(.single(1)); XCTAssertFalse(latest.cancelled); latest.send(2); XCTAssertEqual(values,[1,2]); operation.dispose(); XCTAssertTrue(latest.cancelled)
    }
    func testThrottledReentrantPendingSurvivesHeadCompletion() {
        let pipe = ValuePipe<Signal<Int,Failure>>(); let next = Pending(); var values: [Int] = []
        let operation = (pipe.signal() |> castError(Failure.self) |> throttled).start(next: { value in values.append(value); if value == 1 { pipe.putNext(next.signal) } })
        pipe.putNext(.single(1)); XCTAssertFalse(next.cancelled); next.send(2); XCTAssertEqual(values,[1,2]); operation.dispose()
    }
    func testQueuePreservesFifoAndDefersOuterCompletion() {
        let outer = SignalPipe<Signal<Int,Failure>>(); let first = Pending(); let second = Pending(); var values: [Int] = []; var complete = 0
        let operation = (outer.signal |> queue).start(next: { values.append($0) }, completed: { complete += 1 })
        outer.send(first.signal); outer.send(second.signal); outer.finish()
        XCTAssertEqual(first.starts,1); XCTAssertEqual(second.starts,0); XCTAssertEqual(complete,0)
        first.send(1); first.finish(); second.send(2); XCTAssertEqual(complete,0); second.finish(); XCTAssertEqual(values,[1,2]); XCTAssertEqual(complete,1); operation.dispose()
    }
    func testSwitchCancelsPreviousAndWaitsForLatest() {
        let outer = SignalPipe<Signal<Int,Failure>>(); let first = Pending(); let second = Pending(); var complete = 0
        let operation = (outer.signal |> switchToLatest).start(completed: { complete += 1 })
        outer.send(first.signal); outer.send(second.signal); XCTAssertTrue(first.cancelled); XCTAssertFalse(second.cancelled); outer.finish(); XCTAssertEqual(complete,0); second.finish(); XCTAssertEqual(complete,1); operation.dispose()
    }
    func testThrottledDropsIntermediateQueuedWork() {
        let pipe = ValuePipe<Signal<Int,Failure>>(); let first = Pending(); let discarded = Pending(); let last = Pending()
        let operation = (pipe.signal() |> castError(Failure.self) |> throttled).start()
        pipe.putNext(first.signal); pipe.putNext(discarded.signal); pipe.putNext(last.signal); first.finish()
        XCTAssertEqual(discarded.starts,0); XCTAssertEqual(last.starts,1); operation.dispose(); XCTAssertTrue(last.cancelled)
    }
    func testQueueErrorPreventsQueuedWork() {
        let pipe = ValuePipe<Signal<Int,Failure>>(); let first = Pending(); let queued = Pending(); var errors = 0
        let operation = (pipe.signal() |> castError(Failure.self) |> queue).start(error: { _ in errors += 1 })
        pipe.putNext(first.signal); pipe.putNext(queued.signal); first.fail()
        XCTAssertEqual(errors,1); XCTAssertTrue(first.cancelled); XCTAssertEqual(queued.starts,0); operation.dispose()
    }
    func testDisposeDuringSynchronousDeliveryCancelsQueuedWork() {
        let pipe = ValuePipe<Signal<Int,Failure>>(); let queued = Pending(); let holder = MetaDisposable()
        holder.set((pipe.signal() |> castError(Failure.self) |> queue).start(next: { _ in pipe.putNext(queued.signal); holder.dispose() }))
        pipe.putNext(.single(1)); XCTAssertEqual(queued.starts,0)
    }
    func testSynchronousQueuedHeadsKeepAsyncTailOwned() {
        let pipe = ValuePipe<Signal<Int,Failure>>(); let head = Pending(); let tail = Pending(); var values: [Int] = []
        let operation = (pipe.signal() |> castError(Failure.self) |> queue).start(next: { values.append($0) })
        pipe.putNext(head.signal); for value in 0..<100 { pipe.putNext(.single(value)) }; pipe.putNext(tail.signal)
        head.finish(); XCTAssertEqual(values.count,100); XCTAssertFalse(tail.cancelled); tail.send(100); XCTAssertEqual(values.last,100); operation.dispose(); XCTAssertTrue(tail.cancelled)
    }
    func testDisposalReleasesQueuedCaptures() {
        final class Payload {}
        func signal(_ payload: Payload) -> Signal<Int,Failure> { Signal { _ in withExtendedLifetime(payload) {}; return EmptyDisposable } }
        let pipe = ValuePipe<Signal<Int,Failure>>(); let head = Pending()
        let operation = (pipe.signal() |> castError(Failure.self) |> queue).start()
        pipe.putNext(head.signal); var payload: Payload? = Payload(); weak var observed = payload
        pipe.putNext(signal(payload!)); payload = nil; XCTAssertNotNil(observed)
        operation.dispose(); XCTAssertNil(observed)
    }
    func testMapToQueueRetainsNextAsyncOperation() {
        let input = ValuePipe<Int>(); let next = Pending(); var values: [Int] = []
        let operation = (input.signal() |> castError(Failure.self) |> mapToQueue { $0 == 1 ? .single(1) : next.signal }).start(next: { value in values.append(value); if value == 1 { input.putNext(2) } })
        input.putNext(1); next.send(2); XCTAssertEqual(values,[1,2]); operation.dispose()
    }
}
final class SignalPipe<T> {
    var subscriber: Subscriber<T,Failure>?
    var signal: Signal<T,Failure> { Signal { subscriber in self.subscriber = subscriber; return ActionDisposable { self.subscriber = nil } } }
    func send(_ value: T) { subscriber?.putNext(value) }
    func finish() { subscriber?.putCompletion() }
}
