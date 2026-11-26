import Foundation
import XCTest
import SwiftSignalKit

private enum EffectsCase {
    typealias MessageId = Int
    typealias Key = Int
    final class View { var removed = false }
    struct Reference { weak var value: View? }
    struct Value { let key: Key; let view: Reference }
    static func performSubviewRemoval(_ view: View, animated: Bool) { view.removed = true }
    final class Owner {
__EFFECT_DISPOSABLES__
        var animations: [Key: Value] = [:]
        var enqueuedToServer: [Value] = []
        var enqueuedToEnjoy: [Value] = []
        var timers: [MessageId: SwiftSignalKit.Timer] = [:]
        var enjoyTimer: SwiftSignalKit.Timer?
__REMOVE_EFFECTS__
__DISPOSE_EFFECT__
        func load(_ signal: Signal<Int, NoError>, reaction: Bool, action: @escaping (Int) -> Void) {
            let disposable = signal.start(next: action)
            if reaction { reactionDataDisposable.set(disposable, forKey: 1) }
            else { dataDisposable.set(disposable, forKey: 1) }
        }
        deinit { dataDisposable.dispose(); reactionDataDisposable.dispose() }
    }
    final class Payload {}
}

final class EffectsTests: XCTestCase {
    func testDismissCancelsPendingEmojiAndReactionLoads() {
        let owner = EffectsCase.Owner()
        var subscribers: [Subscriber<Int, NoError>] = []
        var canceled = 0
        var rendered: [Int] = []
        let signal = Signal<Int, NoError> { subscriber in
            subscribers.append(subscriber)
            return ActionDisposable { canceled += 1 }
        }
        owner.load(signal, reaction: false, action: { rendered.append($0) })
        owner.load(signal, reaction: true, action: { rendered.append($0) })
        owner.removeAll()
        for subscriber in subscribers { subscriber.putNext(1) }
        XCTAssertEqual(canceled, 2)
        XCTAssertTrue(rendered.isEmpty)
    }
    func testDismissReleasesPayloadRetainedByPendingLoad() {
        let owner = EffectsCase.Owner()
        weak var reference: EffectsCase.Payload?
        do {
            let payload = EffectsCase.Payload()
            reference = payload
            owner.load(Signal { _ in ActionDisposable { withExtendedLifetime(payload) {} } }, reaction: true, action: { _ in })
        }
        XCTAssertNotNil(reference)
        owner.removeAll()
        XCTAssertNil(reference)
    }
    func testEffectsCanLoadAgainAfterDismissal() {
        let owner = EffectsCase.Owner()
        owner.removeAll()
        var rendered: [Int] = []
        owner.load(.single(7), reaction: true, action: { rendered.append($0) })
        XCTAssertEqual(rendered, [7])
        owner.removeAll()
    }
    func testDismissRemovesViewsAndClearsQueuedEventsAndTimers() {
        let owner = EffectsCase.Owner()
        let view = EffectsCase.View()
        let value = EffectsCase.Value(key: 1, view: .init(value: view))
        owner.animations[1] = value
        owner.enqueuedToServer = [value]
        owner.enqueuedToEnjoy = [value]
        var calls = 0
        let timer = SwiftSignalKit.Timer(timeout: 0.01, repeat: false, completion: { calls += 1 }, queue: .mainQueue())
        owner.timers[1] = timer
        owner.enjoyTimer = timer
        timer.start()
        owner.removeAll()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertTrue(view.removed)
        XCTAssertTrue(owner.animations.isEmpty)
        XCTAssertTrue(owner.enqueuedToServer.isEmpty)
        XCTAssertTrue(owner.enqueuedToEnjoy.isEmpty)
        XCTAssertTrue(owner.timers.isEmpty)
        XCTAssertNil(owner.enjoyTimer)
        XCTAssertEqual(calls, 0)
    }
}
