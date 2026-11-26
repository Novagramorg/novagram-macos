import AppKit
import XCTest
@testable import PeerObservationCore

final class ObservationTests: XCTestCase {
    private func drainMainQueue() {
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    private func enqueueFromBackground(_ delivery: @escaping () -> Void) {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            delivery()
            done.signal()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
    }

    func testRepeatedEquivalentPeersReuseSubscriptionAndLatestCallback() {
        let account = Account(), observer = PremiumStatusPeerObservation()
        let peer = TestPeer(1)
        account.postbox.current[peer.id] = peer
        var callbacks: [Int] = []
        for index in 0..<1000 {
            observer.update(peer: index % 2 == 0 ? peer : TestPeer(1), account: account, enabled: true) { _ in callbacks.append(index) }
        }
        XCTAssertEqual(account.postbox.queries, 1)
        XCTAssertEqual(account.postbox.starts, 1)
        XCTAssertEqual(account.postbox.disposals, 0)
        account.postbox.emit(TestPeer(1, 1))
        XCTAssertEqual(callbacks, [999])
        account.postbox.emit(TestPeer(1, 1))
        XCTAssertEqual(callbacks, [999])
        account.postbox.emit(TestPeer(1, 2))
        XCTAssertEqual(callbacks, [999, 999])
    }

    func testReferenceRecreatesSubscriptionForEveryUnchangedBinding() {
        let account = Account(), observer = ReferenceObservation(), peer = TestPeer(1)
        var callbacks: [Int] = []
        for index in 0..<1000 {
            observer.update(peer: peer, account: account, enabled: true) { _ in callbacks.append(index) }
        }
        XCTAssertEqual(account.postbox.starts, 1000)
        XCTAssertEqual(account.postbox.disposals, 999)
        XCTAssertEqual(account.postbox.activeCount, 1)
        account.postbox.emit(TestPeer(1, 1))
        XCTAssertEqual(callbacks, [999])
    }

    func testAccountPeerAndCallerContentChangesRestartObservation() {
        let first = Account(), second = Account(), observer = PremiumStatusPeerObservation()
        let peer = TestPeer(1)
        var seen: [Int64] = []
        observer.update(peer: peer, account: first, enabled: true) { seen.append($0.id.value) }
        observer.update(peer: TestPeer(1, 1), account: first, enabled: true) { seen.append($0.id.value) }
        XCTAssertEqual(first.postbox.starts, 2)
        XCTAssertEqual(first.postbox.disposals, 1)
        observer.update(peer: TestPeer(1, 1), account: second, enabled: true) { seen.append($0.id.value) }
        XCTAssertEqual(first.postbox.activeCount, 0)
        XCTAssertEqual(second.postbox.activeCount, 1)
        observer.update(peer: TestPeer(2), account: second, enabled: true) { seen.append($0.id.value) }
        first.postbox.emit(TestPeer(1, 3))
        second.postbox.emit(TestPeer(1, 3))
        XCTAssertTrue(seen.isEmpty)
        second.postbox.emit(TestPeer(2, 1))
        XCTAssertEqual(seen, [2])
        XCTAssertEqual(second.postbox.starts, 2)
        XCTAssertEqual(second.postbox.activeCount, 1)
    }

    func testChangedCallerPeerStillRefreshesAuthoritativeSnapshot() {
        let observer = PremiumStatusPeerObservation(), account = Account()
        var revisions: [Int] = []
        func bind(_ peer: Peer) {
            observer.update(peer: peer, account: account, enabled: true) { updated in
                revisions.append((updated as! TestPeer).revision)
                bind(updated)
            }
        }
        let initial = TestPeer(1)
        account.postbox.current[initial.id] = initial
        bind(initial)
        account.postbox.emit(TestPeer(1, 2))
        XCTAssertEqual(account.postbox.starts, 1)
        bind(TestPeer(1))
        XCTAssertEqual(revisions, [2, 2])
        XCTAssertEqual(account.postbox.starts, 2)
        XCTAssertEqual(account.postbox.activeCount, 1)
        account.postbox.emit(TestPeer(1, 3))
        XCTAssertEqual(revisions, [2, 2, 3])
        XCTAssertEqual(account.postbox.starts, 2)
        observer.update(peer: initial, account: account, enabled: false) { _ in }
    }

    func testProductionBindingForwardsLatestPresentationAndContext() {
        let account = Account(), control = BindingControl()
        let peer = TestPeer(1)
        let packs1 = InlineStickersContext(), packs2 = InlineStickersContext()
        control.set(peer, account: account, inlinePacksContext: packs1, left: false, color: .red, isSelected: false, isBig: false, animated: false, playTwice: true, isLite: false)
        control.set(TestPeer(1), account: account, inlinePacksContext: packs2, left: true, color: .blue, isSelected: true, isBig: true, animated: true, playTwice: false, isLite: true)
        account.postbox.emit(TestPeer(1, 1))
        XCTAssertEqual(control.rendered.count, 3)
        let last = control.rendered.last!
        XCTAssertEqual((last.peer as! TestPeer).revision, 1)
        XCTAssertTrue(last.account === account)
        XCTAssertTrue(last.inlinePacksContext === packs2)
        XCTAssertEqual(last.color, NSColor.blue)
        XCTAssertTrue(last.left && last.isSelected && last.isBig && last.animated && last.isLite && last.autoupdate)
        XCTAssertFalse(last.playTwice)
        XCTAssertEqual(account.postbox.starts, 1)
        account.postbox.emit(TestPeer(1, 1))
        XCTAssertEqual(control.rendered.count, 3)
    }

    func testDisabledAndMissingPeersDoNotDeliverUpdates() {
        let account = Account(), observer = PremiumStatusPeerObservation(), peer = TestPeer(1)
        var count = 0
        observer.update(peer: peer, account: account, enabled: false) { _ in count += 1 }
        XCTAssertEqual(account.postbox.starts, 0)
        observer.update(peer: peer, account: account, enabled: true) { _ in count += 1 }
        account.postbox.emitMissing(peer.id)
        XCTAssertEqual(count, 0)
        observer.update(peer: peer, account: account, enabled: false) { _ in count += 1 }
        XCTAssertEqual(account.postbox.activeCount, 0)
        account.postbox.emit(TestPeer(1, 1))
        XCTAssertEqual(count, 0)
        observer.update(peer: TestPeer(1, 1), account: account, enabled: true) { _ in count += 1 }
        XCTAssertEqual(account.postbox.starts, 2)
        account.postbox.emit(TestPeer(1, 2))
        XCTAssertEqual(count, 1)
    }

    func testQueuedDeliveryUsesLatestCallbackAndCancelledPeerCannotRender() {
        let account = Account(), observer = PremiumStatusPeerObservation(), peer = TestPeer(1)
        var callbacks: [String] = []
        observer.update(peer: peer, account: account, enabled: true) { _ in callbacks.append("old") }
        let pending = account.postbox.delivery(TestPeer(1, 1))
        enqueueFromBackground(pending)
        observer.update(peer: peer, account: account, enabled: true) { _ in callbacks.append("current") }
        drainMainQueue()
        XCTAssertEqual(callbacks, ["current"])
        let cancelled = account.postbox.delivery(TestPeer(1, 2))
        enqueueFromBackground(cancelled)
        observer.update(peer: TestPeer(2), account: account, enabled: true) { _ in callbacks.append("new peer") }
        drainMainQueue()
        cancelled()
        XCTAssertEqual(callbacks, ["current"])
        account.postbox.emit(TestPeer(2, 1))
        XCTAssertEqual(callbacks, ["current", "new peer"])
    }

    func testImmediateCallbackCanDisableObservationWithoutLeakingSubscription() {
        let account = Account(), observer = PremiumStatusPeerObservation(), peer = TestPeer(1)
        account.postbox.current[peer.id] = TestPeer(1, 1)
        observer.update(peer: peer, account: account, enabled: true) { updated in
            observer.update(peer: updated, account: account, enabled: false) { _ in XCTFail("Disabled") }
        }
        XCTAssertEqual(account.postbox.starts, 1)
        XCTAssertEqual(account.postbox.disposals, 1)
        XCTAssertEqual(account.postbox.activeCount, 0)
    }

    func testImmediateCallbackAccountSwitchKeepsNewSubscription() {
        let first = Account(), second = Account(), observer = PremiumStatusPeerObservation(), peer = TestPeer(1)
        first.postbox.current[peer.id] = TestPeer(1, 1)
        var calls = 0
        observer.update(peer: peer, account: first, enabled: true) { updated in
            observer.update(peer: updated, account: second, enabled: true) { _ in calls += 1 }
        }
        XCTAssertEqual(first.postbox.activeCount, 0)
        XCTAssertEqual(second.postbox.activeCount, 1)
        second.postbox.emit(TestPeer(1, 2))
        XCTAssertEqual(calls, 1)
    }

    func testReferenceExposesImmediateCallbackReplacementBug() {
        let first = Account(), second = Account(), observer = ReferenceObservation(), peer = TestPeer(1)
        first.postbox.current[peer.id] = TestPeer(1, 1)
        observer.update(peer: peer, account: first, enabled: true) { updated in
            observer.update(peer: updated, account: second, enabled: true) { _ in }
        }
        XCTAssertEqual(first.postbox.activeCount, 1)
        XCTAssertEqual(second.postbox.activeCount, 0)
        observer.update(peer: peer, account: first, enabled: false) { _ in }
    }

    func testReleaseAndDisableReleaseSubscriptionsPeersAndCallbacks() {
        final class Token {}
        let account = Account()
        var observer: PremiumStatusPeerObservation? = PremiumStatusPeerObservation()
        weak var weakPeer: TestPeer?
        weak var weakToken: Token?
        do {
            let peer = TestPeer(1), token = Token()
            weakPeer = peer; weakToken = token
            observer!.update(peer: peer, account: account, enabled: true) { _ in withExtendedLifetime(token) {} }
        }
        XCTAssertNotNil(weakPeer)
        XCTAssertNotNil(weakToken)
        observer!.update(peer: TestPeer(2), account: account, enabled: false) { _ in }
        XCTAssertNil(weakPeer)
        XCTAssertNil(weakToken)
        XCTAssertEqual(account.postbox.activeCount, 0)
        observer!.update(peer: TestPeer(1), account: account, enabled: true) { _ in }
        observer = nil
        XCTAssertEqual(account.postbox.activeCount, 0)
        XCTAssertEqual(account.postbox.disposals, 2)
        var control: BindingControl? = BindingControl()
        weak var weakControl = control
        control!.set(TestPeer(1), account: account, inlinePacksContext: nil, left: false, color: nil, isSelected: false, isBig: false, animated: false, isLite: false)
        control = nil
        XCTAssertNil(weakControl)
        XCTAssertEqual(account.postbox.activeCount, 0)
    }

    func testEquivalentRebindingReleasesPreviousPeerAndCallback() {
        final class Token {}
        let account = Account(), observer = PremiumStatusPeerObservation()
        weak var previousPeer: TestPeer?
        weak var previousToken: Token?
        do {
            let peer = TestPeer(1), token = Token()
            previousPeer = peer; previousToken = token
            observer.update(peer: peer, account: account, enabled: true) { _ in withExtendedLifetime(token) {} }
        }
        XCTAssertNotNil(previousPeer)
        XCTAssertNotNil(previousToken)
        observer.update(peer: TestPeer(1), account: account, enabled: true) { _ in }
        XCTAssertNil(previousPeer)
        XCTAssertNil(previousToken)
        XCTAssertEqual(account.postbox.starts, 1)
    }

    func testLiveUpdatesRenderEveryRevisionWithoutRecreatingSubscription() {
        let account = Account(), control = BindingControl()
        control.set(TestPeer(1), account: account, inlinePacksContext: nil, left: false, color: nil, isSelected: false, isBig: false, animated: false, isLite: false)
        for revision in 1...1000 { account.postbox.emit(TestPeer(1, revision)) }
        XCTAssertEqual(control.rendered.map { ($0.peer as! TestPeer).revision }, Array(0...1000))
        XCTAssertEqual(account.postbox.starts, 1)
        XCTAssertEqual(account.postbox.disposals, 0)
        XCTAssertEqual(account.postbox.activeCount, 1)
    }

    func testObservationBenchmark() throws {
        guard ProcessInfo.processInfo.environment["PREMIUM_STATUS_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let iterations = 5000
        var results: [[String: Any]] = []
        for mode in ["same_object", "equal_peer", "changing_peer", "disabled", "new_observer"] {
            let before = ReferenceObservation(), after = PremiumStatusPeerObservation()
            let a = Account(), b = Account(), peer = TestPeer(1)
            a.postbox.emitOnSubscribe = false; b.postbox.emitOnSubscribe = false
            var checksum = 0
            func measure(_ baseline: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for index in 0..<iterations {
                    let value = mode == "equal_peer" ? TestPeer(1) : mode == "changing_peer" ? TestPeer(1, index) : peer
                    let callback: (Peer) -> Void = { checksum += Int($0.id.value) }
                    if baseline {
                        let observer = mode == "new_observer" ? ReferenceObservation() : before
                        observer.update(peer: value, account: a, enabled: mode != "disabled", onUpdate: callback)
                    } else {
                        let observer = mode == "new_observer" ? PremiumStatusPeerObservation() : after
                        observer.update(peer: value, account: b, enabled: mode != "disabled", onUpdate: callback)
                    }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000
            }
            _ = measure(true); _ = measure(false)
            var old: [Double] = [], new: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == 0 { old.append(measure(true)); new.append(measure(false)) }
                else { new.append(measure(false)); old.append(measure(true)) }
            }
            results.append(["scenario": mode, "baseline_us": old.sorted()[4], "candidate_us": new.sorted()[4], "baseline_trials_us": old, "candidate_trials_us": new, "baseline_starts": a.postbox.starts, "candidate_starts": b.postbox.starts, "checksum": checksum])
        }
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": iterations, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/premium-status-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
