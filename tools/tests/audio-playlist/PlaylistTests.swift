import Foundation
import XCTest
import SwiftSignalKit

final class WeakReference<T: AnyObject> { weak var value: T?; init(value: T) { self.value = value } }
final class APSongItem: Equatable {
    static func ==(lhs: APSongItem, rhs: APSongItem) -> Bool { lhs.stableId == rhs.stableId }
    enum State: Equatable { case waiting, stoped, playing(Int) }
    let id: Int
    var stableId: Int { id }
    struct Entry { let index: Int; let version: Int }
    struct Resource { let id: Int; let reference: Int }
    var entry: Entry
    var resource: Resource
    var songName: String
    var performerName: String
    var ext = "mp3"
    let statePromise = Promise<State>()
    var state: State = .waiting { didSet { statePromise.set(.single(state)) } }
    var stateValue: Signal<State, NoError> { statePromise.get() }
    init(_ id: Int) {
        self.id = id
        self.entry = Entry(index: id, version: 0)
        self.resource = Resource(id: id, reference: 0)
        self.songName = "Song \(id)"
        self.performerName = "Artist"
    }
    __METADATA__
}
final class Peer { let displayTitle: String; init(_ title: String) { displayTitle = title } }
typealias MessageId = Int
typealias PeerId = Int
struct TestMedia { let id: Int; func isEqual(to other: TestMedia) -> Bool { id == other.id } }
struct DataAttribute { let data: Data }
struct TimestampAttribute { let timestamp: Int }
enum Stories { struct StoredItem: Equatable {} }
struct StoryEntry: Equatable { func get<T>(_ type: T.Type) -> T? { nil } }
final class Message {
    let id: Int
    let stableVersion: Int
    let media: [TestMedia]
    let peers: [Int: Peer]
    var derivedDataAttribute: DataAttribute?
    var forwardVideoTimestampAttribute: TimestampAttribute?
    var associatedMessages: [Int: Message] = [:]
    var associatedStories: [Int: StoryEntry] = [:]
    init(id: Int, version: Int, media: Int, author: String) {
        self.id = id
        self.stableVersion = version
        self.media = [TestMedia(id: media)]
        self.peers = [id: Peer(author)]
    }
}
struct FileReference { let media: Int }
enum APEntry: Equatable { case song(Message), single(Int), savedMusic(FileReference, Int) }
__MESSAGE_EQUALITY__
__ENTRY_EQUALITY__
typealias APItem = APSongItem
__TRANSITION__
final class Player {
    enum Action { case stop }
    var actionAtEnd = Action.stop
    func pause() {}
}
protocol APDelegate: AnyObject {
    func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool)
    func songDidChanged(song: APSongItem, for controller: APController, animated: Bool)
    func playerDidChangedTimebase(song: APSongItem, for controller: APController, animated: Bool)
    func songDidStopPlaying(song: APSongItem, for controller: APController, animated: Bool)
    func audioDidCompleteQueue(for controller: APController, animated: Bool)
}
final class Listener: NSObject, APDelegate {
    var state: ((APSongItem) -> Void)?
    var changed: ((APSongItem) -> Void)?
    var timebase: ((APSongItem) -> Void)?
    var stopped: ((APSongItem) -> Void)?
    var completed: (() -> Void)?
    func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool) { state?(song) }
    func songDidChanged(song: APSongItem, for controller: APController, animated: Bool) { changed?(song) }
    func playerDidChangedTimebase(song: APSongItem, for controller: APController, animated: Bool) { timebase?(song) }
    func songDidStopPlaying(song: APSongItem, for controller: APController, animated: Bool) { stopped?(song) }
    func audioDidCompleteQueue(for controller: APController, animated: Bool) { completed?() }
}
final class ControlCenter {
    var nowPlaying: Int?
    var clears = 0
    var published: [Int] = []
    var nextEnabled = false
    var prevEnabled = false
    func setupNowPlaying(_ item: APSongItem) { nowPlaying = item.id; published.append(item.id) }
    func updateControlsAvaiability(nextEnabled: Bool, prevEnabled: Bool) { self.nextEnabled = nextEnabled; self.prevEnabled = prevEnabled }
    func clearNowPlaying() { nowPlaying = nil; clears += 1 }
}
final class APController {
    __STATE__
    var state = State.default { didSet { if state != oldValue { notifyGlobalStateChanged(animated: true) } } }
    let items = Atomic<[APItem]>(value: [])
    var current = -1
    var played: [Int] = []
    var mediaPlayer: Player?
    var playbackGeneration: UInt64 = 0
    var playlistGeneration: UInt64 = 0
    var completingPlaylistGeneration: UInt64?
    var listeners: [WeakReference<NSObject>] = []
    let controlCenter = ControlCenter()
    let songStateDisposable = MetaDisposable()
    let statusDisposable = MetaDisposable()
    let timebaseDisposable = MetaDisposable()
    let itemDisposable = MetaDisposable()
    var prevNextDisposable = DisposableSet()
    var _timebase: Int?
    var bufferingStatus: Signal<Int?, NoError> = .single(nil)
    var starts: [Int] = []
    let ready = Promise<Bool>()
    var onPlay: (() -> Void)?
    func stopTimer() {}
    func play(with item: APSongItem) {
        playbackGeneration &+= 1
        mediaPlayer = Player()
        starts.append(item.id)
        state.status = .playing
        onPlay?()
    }
    func choose(_ index: Int) { current = index; dequeueCurrent() }
    func chatUpdate(_ transition: APTransition) {
        let first = Atomic<Bool>(value: false)
        let items = self.items
        let index: Int? = nil
        let apply: (APTransition) -> Void = { [weak self] transition in
            __CHAT_APPLY__
        }
        apply(transition)
    }
    deinit { songStateDisposable.dispose(); statusDisposable.dispose(); timebaseDisposable.dispose(); itemDisposable.dispose(); prevNextDisposable.dispose() }
    __SONG__
    __MERGE__
    __GLOBAL__
    __NOTIFICATIONS__
    __NAVIGATION__
    __FINISH__
    __STOP__
    __CLEANUP__
    __LISTENERS__
}

final class PlaylistTests: XCTestCase {
    func controller(_ count: Int = 3, index: Int = 1) -> APController {
        let controller = APController()
        _ = controller.items.swap((0..<count).map(APSongItem.init))
        controller.choose(index)
        return controller
    }
    func remove(_ indexes: [Int], from c: APController) {
        c.chatUpdate(APTransition(inserted: [], removed: indexes, updated: []))
    }
    func testMergePreservesCurrentIdentityAfterEarlierDeletion() {
        let c = controller(4, index: 2)
        let song = c.song, decoder = c.mediaPlayer
        remove([0], from: c)
        XCTAssertEqual(c.current, 1)
        XCTAssertTrue(c.song === song && c.mediaPlayer === decoder)
        XCTAssertEqual(c.starts, [2])
    }
    func testShuffleBackTracksIdentitiesAfterReorder() {
        let c = controller(4, index: 2)
        c.state.orderState = .random
        c.played = [0, 1]
        c.chatUpdate(APTransition(inserted: [(3, APSongItem(0))], removed: [0], updated: []))
        XCTAssertTrue(c.prev())
        XCTAssertEqual(c.song?.id, 1)
        XCTAssertTrue(c.prev())
        XCTAssertEqual(c.song?.id, 0)
    }
    func testShuffleHistoryDropsDeletedAndInvalidEntries() {
        let c = controller(4, index: 2)
        c.state.orderState = .random
        c.played = [0, 1, -1, 99]
        c.chatUpdate(APTransition(inserted: [(0, APSongItem(9))], removed: [0], updated: []))
        XCTAssertEqual(c.played, [1])
        XCTAssertTrue(c.prev())
        XCTAssertEqual(c.song?.id, 1)
    }
    func testCurrentDeletionSelectsAdjacentSurvivorBothDirections() {
        for order: APController.State.OrderState in [.normal, .reversed] {
            let c = controller(4, index: 2)
            c.state.orderState = order
            remove([2], from: c)
            XCTAssertEqual(c.song?.id, order == .normal ? 1 : 3)
            XCTAssertTrue(c.song === c.currentSong)
            XCTAssertEqual(c.starts.count, 2)
        }
    }
    func testDeletionAdvancesToOnlyRemainingTrack() {
        for order: APController.State.OrderState in [.normal, .reversed] {
            let c = controller(2, index: order == .normal ? 1 : 0)
            c.state.orderState = order
            remove([c.current], from: c)
            XCTAssertEqual(c.song?.id, order == .normal ? 0 : 1)
            XCTAssertEqual(c.current, 0)
            XCTAssertEqual(c.starts.count, 2)
        }
    }
    func testBulkDeletionUsesSurvivingIdentities() {
        for order: APController.State.OrderState in [.normal, .reversed] {
            let c = controller(5, index: 3)
            c.state.orderState = order
            remove([0, 2, 3], from: c)
            XCTAssertEqual(c.song?.id, order == .normal ? 1 : 4)
            XCTAssertTrue(c.song === c.currentSong)
        }
    }
    func testDeletingEndCompletesWithoutWrappingOrRepeatingDeletedTrack() {
        for order: APController.State.OrderState in [.normal, .reversed] {
            for mode: APController.State.RepeatState in [.none, .one] {
                let c = controller(index: order == .normal ? 0 : 2)
                c.state.orderState = order
                c.state.repeatState = mode
                remove([c.current], from: c)
                XCTAssertNil(c.mediaPlayer)
                XCTAssertEqual(c.state.status, .stopped)
                XCTAssertEqual(c.current, -1)
                XCTAssertEqual(c.starts.count, 1)
                XCTAssertEqual(c.controlCenter.clears, 1)
            }
        }
    }
    func testDeletingEndWrapsOnlyForRepeatAll() {
        for order: APController.State.OrderState in [.normal, .reversed] {
            let c = controller(index: order == .normal ? 0 : 2)
            c.state.orderState = order
            c.state.repeatState = .circle
            remove([c.current], from: c)
            XCTAssertEqual(c.song?.id, order == .normal ? 2 : 0)
            XCTAssertTrue(c.song === c.currentSong)
            XCTAssertEqual(c.starts.count, 2)
        }
    }
    func testPausedDeletionDoesNotStartAnotherTrack() {
        let c = controller()
        c.state.status = .paused
        remove([1], from: c)
        XCTAssertEqual(c.starts, [1])
        XCTAssertNil(c.mediaPlayer)
        XCTAssertEqual(c.state.status, .stopped)
    }
    func testDeletingAllCompletesOnceThroughChatHistoryCallback() {
        let c = controller()
        let listener = Listener()
        var completions = 0
        listener.completed = { completions += 1 }
        c.add(listener: listener)
        remove([0, 1, 2], from: c)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(c.controlCenter.clears, 1)
        XCTAssertEqual(c.current, -1)
        XCTAssertNil(c.mediaPlayer)
    }
    func testDeletionPreservesSelectionMadeByStopObserver() {
        let c = controller(4, index: 2), listener = Listener()
        listener.stopped = { _ in listener.stopped = nil; c.choose(2) }
        c.add(listener: listener)
        remove([2], from: c)
        XCTAssertEqual(c.song?.id, 3)
        XCTAssertEqual(c.starts, [2, 3])
        XCTAssertEqual(c.controlCenter.nowPlaying, 3)
    }
    func testMergeRefreshesTransportAvailabilityWithoutPlaybackEvent() {
        let c = controller(2, index: 0)
        c.state.status = .paused
        let listener = Listener()
        var availability: [Bool] = []
        listener.state = { _ in availability.append(c.nextEnabled) }
        c.add(listener: listener)
        XCTAssertTrue(c.controlCenter.nextEnabled)
        remove([1], from: c)
        XCTAssertFalse(c.controlCenter.nextEnabled)
        XCTAssertFalse(c.controlCenter.prevEnabled)
        XCTAssertEqual(c.starts, [0])
        XCTAssertEqual(availability, [false])
    }
    func testMergeRefreshPreservesNewSelectionFromListener() {
        let c = controller(4, index: 1), first = Listener(), second = Listener()
        var events: [Int] = []
        first.state = { item in
            if item.id == 1 { first.state = nil; c.choose(2) }
        }
        second.state = { events.append($0.id) }
        c.add(listener: first)
        c.add(listener: second)
        remove([0], from: c)
        XCTAssertEqual(c.song?.id, 3)
        XCTAssertFalse(events.contains(1))
        XCTAssertEqual(c.controlCenter.nowPlaying, 3)
    }
    func testEmptyTransitionDoesNotRepublishPlayerState() {
        let c = controller(), listener = Listener()
        var calls = 0
        listener.state = { _ in calls += 1 }
        c.add(listener: listener)
        c.merge(with: APTransition(inserted: [], removed: [], updated: []))
        XCTAssertEqual(calls, 0)
    }
    func testInitialMergeDoesNotStartPlayback() {
        let c = APController()
        c.merge(with: APTransition(inserted: [(0, APSongItem(7))], removed: [], updated: []))
        XCTAssertTrue(c.starts.isEmpty)
        XCTAssertEqual(c.current, -1)
        XCTAssertEqual(c.currentSong?.id, 7)
    }
    func testMetadataEditPreservesCurrentObjectPlaybackAndState() {
        let c = controller()
        let song = c.song!, decoder = c.mediaPlayer
        song.state = .playing(47)
        let updated = APSongItem(1)
        updated.songName = "Edited title"
        updated.performerName = "Updated artist"
        updated.entry = APSongItem.Entry(index: 1, version: 8)
        updated.resource = APSongItem.Resource(id: 1, reference: 12)
        updated.ext = "m4a"
        c.chatUpdate(APTransition(inserted: [], removed: [], updated: [(1, updated)]))
        XCTAssertTrue(c.currentSong === song && c.song === song && c.mediaPlayer === decoder)
        XCTAssertEqual(c.currentSong?.state, .playing(47))
        XCTAssertEqual(song.songName, "Edited title")
        XCTAssertEqual(song.performerName, "Updated artist")
        XCTAssertEqual(song.entry.version, 8)
        XCTAssertEqual(song.resource.reference, 12)
        XCTAssertEqual(song.ext, "m4a")
        XCTAssertEqual(c.starts, [1])
    }
    func testPausedMetadataUpdateDoesNotResumeOrReplacePlayer() {
        let c = controller()
        c.state.status = .paused
        let song = c.song!, player = c.mediaPlayer
        let updated = APSongItem(1)
        updated.songName = "Edited while paused"
        c.chatUpdate(APTransition(inserted: [], removed: [], updated: [(1, updated)]))
        XCTAssertTrue(c.currentSong === song && c.mediaPlayer === player)
        XCTAssertEqual(c.state.status, .paused)
        XCTAssertEqual(song.songName, "Edited while paused")
        XCTAssertEqual(c.starts, [1])
    }
    func testResourceReplacementRestartsCurrentPlayer() {
        let c = controller(), old = c.song, decoder = c.mediaPlayer
        let updated = APSongItem(1)
        updated.resource = APSongItem.Resource(id: 101, reference: 0)
        c.chatUpdate(APTransition(inserted: [], removed: [], updated: [(1, updated)]))
        XCTAssertTrue(c.song === updated && c.currentSong === updated)
        XCTAssertFalse(c.mediaPlayer === decoder)
        XCTAssertEqual(old?.state, .stoped)
        XCTAssertEqual(c.starts, [1, 1])
        XCTAssertEqual(c.state.status, .playing)
    }
    func testPausedResourceReplacementStopsWithoutPlayingReplacement() {
        let c = controller()
        c.state.status = .paused
        let updated = APSongItem(1)
        updated.resource = APSongItem.Resource(id: 101, reference: 0)
        c.chatUpdate(APTransition(inserted: [], removed: [], updated: [(1, updated)]))
        XCTAssertNil(c.mediaPlayer)
        XCTAssertEqual(c.state.status, .stopped)
        XCTAssertEqual(c.starts, [1])
        c.dequeueCurrent()
        XCTAssertTrue(c.song === updated)
        XCTAssertEqual(c.starts, [1, 1])
    }
    func testMovedCurrentItemPreservesPlaybackAndUpdatedMetadata() {
        let c = controller(4, index: 1), song = c.song, player = c.mediaPlayer
        let updated = APSongItem(1)
        updated.songName = "Moved title"
        c.chatUpdate(APTransition(inserted: [(3, updated)], removed: [1], updated: []))
        XCTAssertEqual(c.current, 3)
        XCTAssertTrue(c.currentSong === song && c.mediaPlayer === player)
        XCTAssertEqual(c.currentSong?.songName, "Moved title")
        XCTAssertEqual(c.starts, [1])
    }
    func testMetadataUpdatePublishesNewValuesWithoutResettingState() {
        let c = controller(), listener = Listener()
        c.song!.state = .playing(35)
        var received: [(String, APSongItem.State)] = []
        listener.state = { received.append(($0.songName, $0.state)) }
        c.add(listener: listener)
        let updated = APSongItem(1)
        updated.songName = "New name"
        c.chatUpdate(APTransition(inserted: [], removed: [], updated: [(1, updated)]))
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, "New name")
        XCTAssertEqual(received.first?.1, .playing(35))
    }
    func testReinsertedSamePositionPublishesUpdatedMetadata() {
        let c = controller(), listener = Listener()
        var titles: [String] = []
        listener.state = { titles.append($0.songName) }
        c.add(listener: listener)
        let updated = APSongItem(1)
        updated.songName = "Reinserted"
        c.chatUpdate(APTransition(inserted: [(1, updated)], removed: [1], updated: []))
        XCTAssertEqual(titles, ["Reinserted"])
        XCTAssertEqual(c.starts, [1])
    }
    func testUpdatingOtherItemDoesNotMutateCurrentMetadataOrPlayer() {
        let c = controller(), active = c.song, player = c.mediaPlayer
        let updated = APSongItem(2)
        updated.songName = "Other track"
        updated.resource = APSongItem.Resource(id: 102, reference: 0)
        c.chatUpdate(APTransition(inserted: [], removed: [], updated: [(2, updated)]))
        XCTAssertTrue(c.song === active && c.mediaPlayer === player)
        XCTAssertEqual(c.song?.songName, "Song 1")
        c.choose(2)
        XCTAssertTrue(c.song === updated)
        XCTAssertEqual(c.song?.resource.id, 102)
    }
    func testResourceReplacementHonorsStopObserverSelection() {
        let c = controller(), listener = Listener()
        listener.stopped = { _ in listener.stopped = nil; c.choose(2) }
        c.add(listener: listener)
        let updated = APSongItem(1)
        updated.resource = APSongItem.Resource(id: 101, reference: 0)
        c.chatUpdate(APTransition(inserted: [], removed: [], updated: [(1, updated)]))
        XCTAssertEqual(c.song?.id, 2)
        XCTAssertEqual(c.starts, [1, 2])
    }
    func testMessageEntryEqualityDetectsEditsUsingMessageComparator() {
        let original = APEntry.song(Message(id: 1, version: 1, media: 1, author: "First"))
        XCTAssertEqual(original, APEntry.song(Message(id: 1, version: 1, media: 1, author: "First")))
        XCTAssertNotEqual(original, APEntry.song(Message(id: 1, version: 2, media: 1, author: "First")))
        XCTAssertNotEqual(original, APEntry.song(Message(id: 1, version: 1, media: 2, author: "First")))
        XCTAssertNotEqual(original, APEntry.song(Message(id: 1, version: 1, media: 1, author: "Second")))
        XCTAssertNotEqual(original, APEntry.song(Message(id: 2, version: 1, media: 1, author: "First")))
    }
    func testMergeRecoversStaleSelectionUsingActiveSongIdentity() {
        let c = controller(4, index: 2)
        c.current = 99
        remove([0], from: c)
        XCTAssertEqual(c.current, 1)
        XCTAssertEqual(c.song?.id, 2)
        XCTAssertEqual(c.starts, [2])
    }
    func testRandomDeletionSelectsSurvivingTrack() {
        let c = controller(4, index: 2)
        c.state.orderState = .random
        remove([2], from: c)
        XCTAssertNotEqual(c.song?.id, 2)
        XCTAssertTrue(c.song === c.currentSong)
        XCTAssertEqual(c.starts.count, 2)
    }
    func testNormalQueueStopsAtBeginning() {
        let c = controller(index: 0)
        c.audioPlayerDidFinishPlaying()
        XCTAssertNil(c.mediaPlayer)
        XCTAssertEqual(c.state.status, .stopped)
        XCTAssertNil(c.controlCenter.nowPlaying)
    }
    func testReversedQueueStopsAtEnd() {
        let c = controller(index: 2)
        c.state.orderState = .reversed
        c.audioPlayerDidFinishPlaying()
        XCTAssertEqual(c.starts, [2])
        XCTAssertNil(c.mediaPlayer)
        XCTAssertEqual(c.state.status, .stopped)
        XCTAssertNil(c.controlCenter.nowPlaying)
    }
    func testNormalAndReversedAdvanceUntilEnd() {
        let normal = controller(index: 2)
        normal.audioPlayerDidFinishPlaying()
        XCTAssertEqual(normal.current, 1)
        XCTAssertEqual(normal.starts, [2, 1])
        let reversed = controller(index: 0)
        reversed.state.orderState = .reversed
        reversed.audioPlayerDidFinishPlaying()
        XCTAssertEqual(reversed.current, 1)
        XCTAssertEqual(reversed.starts, [0, 1])
    }
    func testRepeatAllRestartsSingleTrack() {
        let c = controller(1, index: 0)
        c.state.repeatState = .circle
        c.audioPlayerDidFinishPlaying()
        XCTAssertEqual(c.starts, [0, 0])
        XCTAssertNotNil(c.mediaPlayer)
        XCTAssertEqual(c.controlCenter.nowPlaying, 0)
    }
    func testRepeatAllWrapsBothDirections() {
        let normal = controller(index: 0)
        normal.state.repeatState = .circle
        normal.audioPlayerDidFinishPlaying()
        XCTAssertEqual(normal.starts, [0, 2])
        let reversed = controller(index: 2)
        reversed.state.repeatState = .circle
        reversed.state.orderState = .reversed
        reversed.audioPlayerDidFinishPlaying()
        XCTAssertEqual(reversed.starts, [2, 0])
    }
    func testRepeatOneRestartsCurrentTrack() {
        let c = controller()
        c.state.repeatState = .one
        c.audioPlayerDidFinishPlaying()
        XCTAssertEqual(c.starts, [1, 1])
        XCTAssertNotNil(c.mediaPlayer)
    }
    func testInitialDefaultIndexIsNormalized() {
        let c = APController()
        _ = c.items.swap([APSongItem(0), APSongItem(1)])
        c.dequeueCurrent()
        XCTAssertEqual(c.current, 0)
        c.audioPlayerDidFinishPlaying()
        XCTAssertEqual(c.starts, [0])
        XCTAssertEqual(c.state.status, .stopped)
    }
    func testEmptyPlaylistDoesNotStartOrCrash() {
        let c = APController()
        c.dequeueCurrent()
        c.state.repeatState = .circle
        c.audioPlayerDidFinishPlaying()
        XCTAssertTrue(c.starts.isEmpty)
        XCTAssertNil(c.mediaPlayer)
    }
    func testCompletionCleanupStillNotifiesRemainingListeners() {
        let c = controller(), first = Listener(), second = Listener()
        var completions = 0
        first.completed = { c.cleanup() }
        second.completed = { completions += 1 }
        c.add(listener: first)
        c.add(listener: second)
        c.complete()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(c.state.status, .stopped)
        XCTAssertNil(c.mediaPlayer)
        XCTAssertNil(c.controlCenter.nowPlaying)
    }
    func testCompletionCallbackStartingNewTrackPreservesNewPlayback() {
        let c = controller(), first = Listener(), second = Listener()
        var staleCompletions = 0
        first.completed = { c.choose(2) }
        second.completed = { staleCompletions += 1 }
        c.add(listener: first)
        c.add(listener: second)
        c.complete()
        XCTAssertEqual(c.starts, [1, 2])
        XCTAssertNotNil(c.mediaPlayer)
        XCTAssertEqual(c.state.status, .playing)
        XCTAssertEqual(c.controlCenter.nowPlaying, 2)
        XCTAssertEqual(staleCompletions, 0)
        XCTAssertEqual(c.listeners.count, 2)
    }
    func testCompletionStateCallbackStartingNewTrackPreservesNewPlayback() {
        let c = controller(), listener = Listener()
        listener.state = { _ in
            if c.state.status == .stopped {
                listener.state = nil
                c.choose(2)
            }
        }
        c.add(listener: listener)
        c.complete()
        XCTAssertEqual(c.starts, [1, 2])
        XCTAssertNotNil(c.mediaPlayer)
        XCTAssertEqual(c.controlCenter.nowPlaying, 2)
        XCTAssertEqual(c.state.status, .playing)
    }
    func testRecursiveCompletionIsCoalesced() {
        let c = controller(), listener = Listener()
        var calls = 0
        listener.completed = {
            calls += 1
            if calls < 3 { c.complete() }
        }
        c.add(listener: listener)
        c.complete()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(c.controlCenter.clears, 1)
    }
    func testCompletionCannotRepublishOldNowPlayingAfterClear() {
        let c = controller()
        c.song?.state = .playing(1)
        c.complete()
        XCTAssertNil(c.controlCenter.nowPlaying)
        XCTAssertEqual(c.controlCenter.clears, 1)
    }
    func testFinishStopCallbackDoesNotAdvanceNewSelection() {
        let c = controller(index: 2), listener = Listener()
        listener.stopped = { _ in
            listener.stopped = nil
            c.choose(1)
        }
        c.add(listener: listener)
        c.audioPlayerDidFinishPlaying()
        XCTAssertEqual(c.starts, [2, 1])
        XCTAssertEqual(c.current, 1)
        XCTAssertNotNil(c.mediaPlayer)
    }
    func testDequeueStopCallbackNewSelectionWins() {
        let c = controller(index: 0), listener = Listener()
        listener.stopped = { _ in
            listener.stopped = nil
            c.choose(2)
        }
        c.add(listener: listener)
        c.choose(1)
        XCTAssertEqual(c.starts, [0, 2])
        XCTAssertEqual(c.song?.id, 2)
        XCTAssertEqual(c.controlCenter.nowPlaying, 2)
    }
    func testImmediateSongStateReentryKeepsNewestSubscription() {
        let c = controller(index: 0), listener = Listener()
        c.pullItems[1].state = .playing(1)
        listener.state = { item in
            if item.id == 1 { listener.state = nil; c.choose(2) }
        }
        c.add(listener: listener)
        c.choose(1)
        XCTAssertEqual(c.starts, [0, 2])
        XCTAssertEqual(c.song?.id, 2)
        c.controlCenter.published.removeAll()
        c.pullItems[2].state = .playing(2)
        XCTAssertEqual(c.controlCenter.published, [2])
        c.pullItems[1].state = .playing(3)
        XCTAssertEqual(c.controlCenter.published, [2])
    }
    func testPlayCallbackNewSelectionDoesNotPublishOldSong() {
        let c = controller(index: 0), listener = Listener()
        var changes: [Int] = []
        listener.changed = { changes.append($0.id) }
        c.add(listener: listener)
        c.onPlay = { c.onPlay = nil; c.choose(2) }
        c.choose(1)
        XCTAssertEqual(c.song?.id, 2)
        XCTAssertEqual(changes, [2])
        XCTAssertEqual(c.controlCenter.nowPlaying, 2)
    }
    func testNotificationsStopDispatchingOldSongAfterReentry() {
        for kind in 0..<4 {
            let c = controller(index: 0), first = Listener(), second = Listener()
            var received: [(Int, Int?)] = []
            let change: (APSongItem) -> Void = { item in if item.id == 0 { c.choose(2) } }
            let record: (APSongItem) -> Void = { received.append(($0.id, c.song?.id)) }
            switch kind {
            case 0: first.state = change; second.state = record
            case 1: first.changed = change; second.changed = record
            case 2: first.timebase = change; second.timebase = record
            default: first.stopped = change; second.stopped = record
            }
            c.add(listener: first)
            c.add(listener: second)
            let old = c.song!
            switch kind {
            case 0: first.state = { item in first.state = nil; change(item) }; c.notifyStateChanged(item: old, animated: false)
            case 1: first.changed = { item in first.changed = nil; change(item) }; c.notifySongChanged(item: old, animated: false)
            case 2: first.timebase = { item in first.timebase = nil; change(item) }; c.notifySongDidChangedTimebase(item: old, animated: false)
            default: first.stopped = { item in first.stopped = nil; change(item) }; c.notifySongDidStopPlaying(item: old, animated: false)
            }
            XCTAssertEqual(c.song?.id, 2)
            XCTAssertFalse(received.contains(where: { $0.0 != $0.1 }), "kind \(kind): \(received)")
            XCTAssertEqual(c.controlCenter.nowPlaying, 2)
        }
    }
    func testRetiredSongNotificationIsIgnored() {
        let c = controller(index: 0), old = APSongItem(99), listener = Listener()
        var count = 0
        listener.state = { _ in count += 1 }
        listener.changed = { _ in count += 1 }
        listener.timebase = { _ in count += 1 }
        listener.stopped = { _ in count += 1 }
        c.add(listener: listener)
        c.notifyStateChanged(item: old, animated: false)
        c.notifySongChanged(item: old, animated: false)
        c.notifySongDidChangedTimebase(item: old, animated: false)
        c.notifySongDidStopPlaying(item: old, animated: false)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(c.controlCenter.nowPlaying, 0)
    }
}
