import Foundation
import XCTest
import SwiftSignalKit

__RESOURCE__

enum Status { case Local, Remote, Fetching(Bool, Float), Paused(Float) }
struct Resource { let id = 1 }
struct DataValue { let complete: Bool; let path: String }
enum Content { case audio }
func link(path: String?, ext: String) -> String? { path.map { $0 + "." + ext } }
final class MediaBox {
    let statusPipe = ValuePipe<Status>()
    let dataPipe = ValuePipe<DataValue>()
    var fetches = 0
    var statuses = 0
    var dataObservers = 0
    var completeStatusImmediately = false
    var initialStatus: Status?
    var initialData: DataValue?
    var completeFetchImmediately = false
    func resourceStatus(_ resource: Resource) -> Signal<Status, NoError> {
        Signal { subscriber in
            self.statuses += 1
            let inner = self.statusPipe.signal().start(next: subscriber.putNext)
            if let value = self.initialStatus { subscriber.putNext(value) }
            if self.completeStatusImmediately { subscriber.putCompletion() }
            return ActionDisposable { self.statuses -= 1; inner.dispose() }
        }
    }
    func resourceData(_ resource: Resource) -> Signal<DataValue, NoError> {
        Signal { subscriber in
            self.dataObservers += 1
            let inner = self.dataPipe.signal().start(next: subscriber.putNext)
            if let value = self.initialData { subscriber.putNext(value) }
            return ActionDisposable { self.dataObservers -= 1; inner.dispose() }
        }
    }
}
final class Postbox { let mediaBox: MediaBox; init(_ box: MediaBox) { mediaBox = box } }
final class Account { let postbox: Postbox; init(_ box: MediaBox) { postbox = Postbox(box) } }
func fetchedMediaResource(mediaBox: MediaBox, userLocation: Int, userContentType: Content, reference: Int) -> Signal<Void, NoError> {
    Signal { subscriber in
        mediaBox.fetches += 1
        if mediaBox.completeFetchImmediately { subscriber.putCompletion() }
        return ActionDisposable { mediaBox.fetches -= 1 }
    }
}
final class APSongItem {
    let account: Account
    let resource = Resource()
    let reference = 1
    let userLocation = 1
    let ext = "mp3"
    enum State { case stoped }
    var state = State.stoped
    let fetchDisposable = MetaDisposable()
    init(_ box: MediaBox) { account = Account(box) }
    __PULL__
}

final class Player {
    enum Action { case stop }
    var actionAtEnd = Action.stop
    func pause() {}
}
final class APController {
    var playbackGeneration: UInt64 = 0
    var song: APSongItem?
    var mediaPlayer: Player? = Player()
    let statusDisposable = MetaDisposable()
    let timebaseDisposable = MetaDisposable()
    let itemDisposable = MetaDisposable()
    var prevNextDisposable = DisposableSet()
    var _timebase: Int?
    var bufferingStatus: Signal<Int?, NoError> = .single(nil)
    func stopTimer() {}
    func notifySongDidStopPlaying(item: APSongItem, animated: Bool) {}
    __STOP__
}

final class ResourceTests: XCTestCase {
    func testCreatingSignalDoesNotStartDownload() {
        let box = MediaBox()
        let item = APSongItem(box)
        let signal = item.pullResource()
        XCTAssertEqual(box.fetches, 0)
        XCTAssertEqual(box.statuses, 0)
        withExtendedLifetime((item, signal)) {}
    }
    func testDisposalReleasesFetchWhileSongRemainsInPlaylist() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        let disposable = item.pullResource().start()
        XCTAssertEqual(box.fetches, 1)
        XCTAssertEqual(box.statuses, 1)
        disposable.dispose()
        XCTAssertEqual(box.fetches, 0)
        XCTAssertEqual(box.statuses, 0)
        withExtendedLifetime(item) {}
    }
    func testControllerStopCancelsOwnedDownloadButPreservesExplicitDownload() {
        let box = MediaBox()
        let item = APSongItem(box), controller = APController()
        controller.song = item
        let explicitDownload = fetchedMediaResource(mediaBox: box, userLocation: 1, userContentType: .audio, reference: 1).start()
        controller.itemDisposable.set(item.pullResource().start())
        XCTAssertEqual(box.fetches, 2)
        controller.stop()
        XCTAssertEqual(box.fetches, 1)
        XCTAssertEqual(box.statuses, 0)
        XCTAssertTrue(controller.song === item)
        explicitDownload.dispose()
        XCTAssertEqual(box.fetches, 0)
    }
    func testSubscriptionsHaveIndependentFetchOwnership() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        let signal = item.pullResource()
        let first = signal.start(), second = signal.start()
        XCTAssertEqual(box.fetches, 2)
        XCTAssertEqual(box.statuses, 2)
        first.dispose()
        XCTAssertEqual(box.fetches, 1)
        XCTAssertEqual(box.statuses, 1)
        second.dispose()
        XCTAssertEqual(box.fetches, 0)
        XCTAssertEqual(box.statuses, 0)
    }
    func testPlaybackDisposalDoesNotCancelIndependentDownload() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        let external = fetchedMediaResource(mediaBox: box, userLocation: 1, userContentType: .audio, reference: 1).start()
        let playback = item.pullResource().start()
        XCTAssertEqual(box.fetches, 2)
        playback.dispose()
        XCTAssertEqual(box.fetches, 1)
        external.dispose()
        XCTAssertEqual(box.fetches, 0)
    }
    func testLocalDataSubscriptionIsReleasedWithPlayback() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        var values: [APResource] = []
        let disposable = item.pullResource().start(next: { values.append($0) })
        box.statusPipe.putNext(.Local)
        XCTAssertEqual(box.dataObservers, 1)
        box.dataPipe.putNext(DataValue(complete: false, path: "/tmp/audio"))
        XCTAssertTrue(values.isEmpty)
        box.dataPipe.putNext(DataValue(complete: true, path: "/tmp/audio"))
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.path, "/tmp/audio.mp3")
        disposable.dispose()
        XCTAssertEqual(box.dataObservers, 0)
        XCTAssertEqual(box.statuses, 0)
        XCTAssertEqual(box.fetches, 0)
    }
    func testFetchingPausedAndRemoteMapping() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        var values: [APResource] = []
        let disposable = item.pullResource().start(next: { values.append($0) })
        box.statusPipe.putNext(.Fetching(true, 0.3))
        box.statusPipe.putNext(.Paused(0.6))
        box.statusPipe.putNext(.Remote)
        XCTAssertEqual(values.map(\.progress), [0.3, 0.6])
        XCTAssertTrue(values.allSatisfy { !$0.complete && $0.path.isEmpty })
        disposable.dispose()
    }
    func testEarlyConsumerCompletionCancelsFetch() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        box.initialStatus = .Fetching(true, 0.2)
        var completed = false
        let disposable = (item.pullResource() |> take(1)).start(completed: { completed = true })
        XCTAssertTrue(completed)
        XCTAssertEqual(box.fetches, 0)
        XCTAssertEqual(box.statuses, 0)
        disposable.dispose()
    }
    func testSourceCompletionCancelsFetch() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        box.completeStatusImmediately = true
        var completed = false
        let disposable = item.pullResource().start(completed: { completed = true })
        XCTAssertTrue(completed)
        XCTAssertEqual(box.fetches, 0)
        XCTAssertEqual(box.statuses, 0)
        disposable.dispose()
    }
    func testCompletedFetchDoesNotEndStatusObservation() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        box.completeFetchImmediately = true
        var completed = false
        let disposable = item.pullResource().start(completed: { completed = true })
        XCTAssertFalse(completed)
        XCTAssertEqual(box.fetches, 0)
        XCTAssertEqual(box.statuses, 1)
        disposable.dispose()
        XCTAssertEqual(box.statuses, 0)
    }
    func testDisposedOldSessionCannotStopReplacementFetch() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        let holder = MetaDisposable()
        let first = item.pullResource().start()
        holder.set(first)
        holder.set(item.pullResource().start())
        first.dispose()
        XCTAssertEqual(box.fetches, 1)
        holder.dispose()
        XCTAssertEqual(box.fetches, 0)
    }
    func testSignalDoesNotRetainSongAndRemainsUsable() {
        let box = MediaBox()
        var item: APSongItem? = APSongItem(box)
        weak var weakItem = item
        let signal = item!.pullResource()
        item = nil
        XCTAssertNil(weakItem)
        var received = 0
        let disposable = signal.start(next: { _ in received += 1 })
        box.statusPipe.putNext(.Fetching(true, 0.5))
        XCTAssertEqual(received, 1)
        XCTAssertEqual(box.fetches, 1)
        disposable.dispose()
        XCTAssertEqual(box.fetches, 0)
    }
    func testQueuedProgressCannotDeliverAfterDisposal() {
        let box = MediaBox(), item: APSongItem
        item = APSongItem(box)
        var received = 0
        let disposable = item.pullResource().start(next: { _ in received += 1 })
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { box.statusPipe.putNext(.Fetching(true, 0.5)); group.leave() }
        group.wait()
        disposable.dispose()
        let done = expectation(description: "drain")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(received, 0)
        XCTAssertEqual(box.fetches, 0)
    }
}
