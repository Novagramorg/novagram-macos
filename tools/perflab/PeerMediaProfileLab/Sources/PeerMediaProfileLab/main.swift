import Cocoa
import SwiftSignalKit

var checks = 0
var randomState: UInt64 = 0x5f7ab3e9
var checksum = 0

func random(_ count: Int) -> Int {
    randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
    return Int((randomState >> 32) % UInt64(count))
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

func history(_ count: Int, months: Int = 1) -> [Message] {
    (0..<count).map { index in
        Message(Int32(index + 1), timestamp: 1_735_776_000 + Int32(index % months) * 2_678_400 + Int32(index / months))
    }
}

for sample in 0..<1_200 {
    let count = sample < 10 ? sample : random(300)
    var messages = history(count, months: sample % 12 + 1)
    if sample % 3 == 0 {
        messages.reverse()
    } else if !messages.isEmpty {
        for index in messages.indices { messages.swapAt(index, random(messages.count)) }
    }
    if sample % 5 == 0, let first = messages.first {
        messages.append(first)
        messages.append(Message(first.id.id, timestamp: first.timestamp, version: 1))
    }
    if sample % 7 == 0, let first = messages.first {
        first.expanded = [Message(first.id.id, timestamp: first.timestamp, namespace: 1_048_577), Message(first.id.id, timestamp: first.timestamp, namespace: 1_048_578)]
    }
    let state = [PeerMediaUpdateState.history, .search, .loading][sample % 3]
    let update = PeerMediaUpdate(messages: messages, updateType: state)
    let delta = [TimeInterval(0), 3600, -3600, 86400][sample % 4]
    let baseline = referenceConvertEntries(from: update, tags: .file, timeDifference: delta, isExternalSearch: sample % 2 == 0)
    let candidate = convertEntries(from: update, tags: .file, timeDifference: delta, isExternalSearch: sample % 2 == 0)
    check(candidate == baseline, "List parity \(sample)")
    check(candidate.map { $0.stableId } == baseline.map { $0.stableId }, "Stable IDs \(sample)")
}

let activityPipe = ValuePipe<[(PeerId, PeerInputActivity)]>()
var oldActivityUpdates: [[PeerId: PeerInputActivity]] = []
var newActivityUpdates: [[PeerId: PeerInputActivity]] = []
let oldActivitySubscription = referenceActivities(activityPipe.signal()).start(next: { oldActivityUpdates.append($0) })
let newActivitySubscription = profileActivities(activityPipe.signal()).start(next: { newActivityUpdates.append($0) })
for sample in 0..<500 {
    let values: [(PeerId, PeerInputActivity)] = (0..<random(40)).map { index in
        (PeerId(Int64(index % 13)), index % 2 == 0 ? .typing : .uploading(Int32(sample)))
    }
    activityPipe.putNext(values)
    activityPipe.putNext(values)
    check(oldActivityUpdates.last == newActivityUpdates.last, "Activity payload \(sample)")
}
let deduplicated = oldActivityUpdates.reduce(into: [[PeerId: PeerInputActivity]]()) { result, update in
    if result.last != update { result.append(update) }
}
check(newActivityUpdates == deduplicated, "Only identical activity dictionaries suppressed")
check(oldActivityUpdates.count == 1_000, "All reference events delivered")
check(newActivityUpdates.count < oldActivityUpdates.count, "Repeated profile updates suppressed")
activityPipe.putNext([(PeerId(1), .typing), (PeerId(1), .uploading(17))])
check(newActivityUpdates.last?[PeerId(1)] == .uploading(17), "Last duplicate peer wins")
activityPipe.putNext([])
check(newActivityUpdates.last?.isEmpty == true, "Activity removal delivered")
oldActivitySubscription.dispose()
newActivitySubscription.dispose()

let tabBaseline = ReferenceTabHarness()
let tabCandidate = TabHarness()
var oldTabs: [[PeerMediaCollectionMode]] = []
var newTabs: [[PeerMediaCollectionMode]] = []
let oldTabsSubscription = tabBaseline.stream().start(next: { oldTabs.append($0.tabs) })
let newTabsSubscription = tabCandidate.stream().start(next: { newTabs.append($0.tabs) })
let tabCases: [TabData] = [([.photoOrVideo, .file], .photoOrVideo, false), ([.photoOrVideo, .file], .photoOrVideo, true), ([.photoOrVideo, .file], .file, true), ([.file], .file, true), ([], nil, true)]
for value in tabCases {
    for _ in 0..<100 {
        tabBaseline.pipe.putNext(value)
        tabCandidate.pipe.putNext(value)
    }
}
check(newTabs == oldTabs, "Tab outputs preserved")
check(newTabs.count == tabCases.count, "Meaningful tab changes delivered")
check(tabBaseline.preparations == 400, "Reference repeats tab preparation")
check(tabCandidate.preparations == 4, "Candidate prepares only distinct tab states")
oldTabsSubscription.dispose()
newTabsSubscription.dispose()

let pendingTabs = TabHarness()
pendingTabs.automaticallyReady = false
var pendingOutputs: [TabData] = []
let pendingSubscription = pendingTabs.stream().start(next: { pendingOutputs.append($0) })
for _ in 0..<100 {
    pendingTabs.pipe.putNext(([.photoOrVideo, .file], .photoOrVideo, true))
}
check(pendingTabs.preparations == 1 && pendingOutputs.isEmpty, "Unready tab is prepared once and still awaited")
pendingTabs.pipe.putNext(([.photoOrVideo, .file], .file, true))
pendingTabs.controller(for: .photoOrVideo).ready.set(.single(true))
check(pendingOutputs.isEmpty, "Late readiness of previous tab is ignored")
pendingTabs.controller(for: .file).ready.set(.single(true))
check(pendingOutputs.count == 1 && pendingOutputs.last?.selected == .file, "Selected tab emits when ready")
pendingTabs.pipe.putNext(([.file], .file, true))
check(pendingOutputs.count == 2 && pendingOutputs.last?.tabs == [.file], "Tab removal still propagates")
pendingSubscription.dispose()

func referenceSizing(width: CGFloat, height: CGFloat, maximumColumns: Int) -> (Int, Int) {
    var columns = maximumColumns
    var cellWidth: CGFloat = 0
    while true {
        cellWidth = (width - CGFloat(columns * 2)) / CGFloat(columns)
        if cellWidth >= 90 { break }
        columns -= 1
    }
    return (columns, Int((height / cellWidth) * CGFloat(columns) + CGFloat(columns)))
}

for step in 368..<8_000 {
    let width = CGFloat(step) / 4
    for columns in [4, 7] {
        let sizing = PeerMediaGridSizing(width: width, maximumColumns: columns)
        for height in [CGFloat(0), 1, 90, 239.5, 600, 1000] {
            let old = referenceSizing(width: width, height: height, maximumColumns: columns)
            check(sizing.columns == old.0 && sizing.itemCount(height: height) == old.1, "Normal geometry parity \(width)/\(height)/\(columns)")
        }
    }
}
for width in [CGFloat(-1000), -74, -1, 0, 0.1, 1, 14, 73, 91, 91.999, .nan, .infinity, -.infinity] {
    for height in [CGFloat(-1), 0, 1, 600, .nan, .infinity, .greatestFiniteMagnitude] {
        for maximum in [4, 7] {
            let sizing = PeerMediaGridSizing(width: width, maximumColumns: maximum)
            check(sizing.columns == 1, "Narrow grid retains one column")
            check(sizing.itemCount(height: height) > 0, "Narrow grid requests a nonempty page")
        }
    }
}
for width in [CGFloat(92), 184, 276, 368, 460, 552, 644] {
    for value in [width.nextDown, width, width.nextUp] where value >= 92 {
        let new = PeerMediaGridSizing(width: value, maximumColumns: 7)
        let old = referenceSizing(width: value, height: 501.5, maximumColumns: 7)
        check(new.columns == old.0 && new.itemCount(height: 501.5) == old.1, "Threshold rounding")
    }
}
for width in [CGFloat(1), 50, 91] {
    let old = referenceSizing(width: width, height: 600, maximumColumns: 7)
    check(old.0 == 0 && old.1 == 0, "Reproduces empty pagination below minimum column width")
}

for count in [0, 1, 2, 20, 1_000] {
    let messages = history(count)
    var state = PeerMediaGifsState(isLoading: false, messages: messages)
    let ordered = Array(messages.reversed())
    for value in [true, false, false, true, true, false] {
        let before = state.messages.withUnsafeBufferPointer { $0.baseAddress }
        state = state.withUpdatedLoading(value)
        check(state.messages == ordered && state.isLoading == value, "GIF loading does not reorder messages")
        check(state.messages.withUnsafeBufferPointer { $0.baseAddress } == before, "GIF loading shares message buffer")
    }
    let baseline = ReferenceGifsState(isLoading: false, messages: []).withUpdatedMessages(messages).withUpdatedLoading(false).withUpdatedLoading(true)
    let candidate = PeerMediaGifsState(isLoading: true, messages: messages)
    check(candidate.messages == baseline.messages, "History update keeps original displayed order")
}
let oldGifs = ReferenceGifsState(isLoading: false, messages: history(2))
check(oldGifs.messages != oldGifs.withUpdatedLoading(true).messages, "Reproduces legacy GIF order bug")

let photos = PeerMediaPhotosState(isLoading: false, messages: history(5), searchState: SearchState(), contentSettings: ContentSettings(), scrollPosition: nil, updateType: nil, side: nil, perRowCount: 4)
var oldPhotos = ReferencePhotosState(isLoading: false, messages: history(5), searchState: SearchState(), contentSettings: ContentSettings(), scrollPosition: nil, updateType: nil, side: nil, perRowCount: 4)
let photoPromise = ValuePromise<PeerMediaPhotosState>(ignoreRepeated: true)
var emittedPhotoStates: [PeerMediaPhotosState] = []
let photoSubscription = photoPromise.get().start(next: { emittedPhotoStates.append($0) })
photoPromise.set(photos)
var currentPhotos = photos
for view in [MessageHistoryView(holeLater: true), MessageHistoryView(holeEarlier: true), MessageHistoryView(earlierId: MessageIndex(history(1)[0])), MessageHistoryView(laterId: MessageIndex(history(1)[0])), MessageHistoryView(anchorIndex: 1), nil] as [MessageHistoryView?] {
    var next = currentPhotos
    next.view = view
    var oldNext = oldPhotos
    oldNext.view = view
    check(oldPhotos == oldNext, "Reference loses history metadata changes")
    check(currentPhotos != next, "History metadata change is observable")
    photoPromise.set(next)
    let delivered = emittedPhotoStates.count
    photoPromise.set(next)
    check(delivered == emittedPhotoStates.count, "Same snapshot remains deduplicated")
    check(emittedPhotoStates.last?.view === view, "Pagination receives latest view")
    if let view = view {
        var equivalent = next
        equivalent.view = MessageHistoryView(laterId: view.laterId, earlierId: view.earlierId, holeLater: view.holeLater, holeEarlier: view.holeEarlier, anchorIndex: view.anchorIndex)
        check(next == equivalent, "Equivalent history snapshots remain deduplicated")
        photoPromise.set(equivalent)
        check(delivered == emittedPhotoStates.count, "Equivalent metadata does not rebuild grid")
    }
    currentPhotos = next
    oldPhotos = oldNext
}
check(emittedPhotoStates.count == 7, "All pagination changes delivered")
photoSubscription.dispose()

var timings: [[String: Any]] = []
@inline(never) func consumeMessages(_ messages: [Message]) -> Int {
    messages.enumerated().reduce(0) { $0 + Int($1.element.id.id) * ($1.offset % 7 + 1) + $1.element.version }
}
@inline(never) func consumeEntries(_ entries: [PeerMediaSharedEntry]) -> Int {
    entries.enumerated().reduce(0) { $0 + Int($1.element.index.id.id) * ($1.offset % 7 + 1) }
}
func bench(_ name: String, iterations: Int, baseline: () -> Int, candidate: () -> Int) {
    check(baseline() == candidate(), "Benchmark parity \(name)")
    var oldTimes: [Double] = []
    var newTimes: [Double] = []
    func measure(_ work: () -> Int) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        var total = 0
        for _ in 0..<iterations { total += work() }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        checksum &+= total
        return Double(elapsed) / Double(iterations) / 1_000
    }
    checksum &+= baseline()
    checksum &+= candidate()
    for round in 0..<7 {
        if round % 2 == 0 {
            oldTimes.append(measure(baseline)); newTimes.append(measure(candidate))
        } else {
            newTimes.append(measure(candidate)); oldTimes.append(measure(baseline))
        }
    }
    let old = oldTimes.sorted()[3]
    let new = newTimes.sorted()[3]
    print("\(name): \(old) -> \(new) us (\(old / new)x)")
    timings.append(["workload": name, "baseline_us": old, "candidate_us": new, "speedup": old / new, "baseline_batches_us": oldTimes, "candidate_batches_us": newTimes])
}
if CommandLine.arguments.contains("--benchmark") {
    for count in [100, 1_000, 5_000] {
        let update = PeerMediaUpdate(messages: history(count), updateType: .history)
        bench("media-list-\(count)", iterations: count == 5_000 ? 10 : 50, baseline: {
            consumeEntries(referenceConvertEntries(from: update, tags: .file, timeDifference: 0, isExternalSearch: false))
        }, candidate: {
            consumeEntries(convertEntries(from: update, tags: .file, timeDifference: 0, isExternalSearch: false))
        })
    }
    for count in [1, 8, 32, 128, 512] {
        let values = (0..<count).map { (PeerId(Int64($0)), PeerInputActivity.typing) }
        bench("profile-cold-subscription-\(count)", iterations: 100, baseline: {
            var result = 0
            referenceActivities(.single(values)).start(next: { result = $0.count }).dispose()
            return result
        }, candidate: {
            var result = 0
            profileActivities(.single(values)).start(next: { result = $0.count }).dispose()
            return result
        })
    }
    for count in [1, 8, 10] {
        let variants = (0..<2).map { variant in
            (0..<count).map { (PeerId(Int64($0)), PeerInputActivity.uploading(Int32(variant))) }
        }
        let oldPipe = ValuePipe<[(PeerId, PeerInputActivity)]>()
        let newPipe = ValuePipe<[(PeerId, PeerInputActivity)]>()
        var oldCount = 0
        var newCount = 0
        var oldIndex = 0
        var newIndex = 0
        let oldSubscription = referenceActivities(oldPipe.signal()).start(next: { oldCount = $0.count })
        let newSubscription = profileActivities(newPipe.signal()).start(next: { newCount = $0.count })
        bench("profile-changed-event-\(count)", iterations: 1_000, baseline: {
            oldIndex = 1 - oldIndex
            oldPipe.putNext(variants[oldIndex])
            return oldCount
        }, candidate: {
            newIndex = 1 - newIndex
            newPipe.putNext(variants[newIndex])
            return newCount
        })
        oldSubscription.dispose()
        newSubscription.dispose()
    }
    for count in [100, 1_000] {
        let messages = history(count)
        bench("legacy-gif-update-\(count)", iterations: 500, baseline: {
            consumeMessages(ReferenceGifsState(isLoading: false, messages: []).withUpdatedMessages(messages).withUpdatedLoading(false).withUpdatedLoading(true).messages)
        }, candidate: {
            consumeMessages(PeerMediaGifsState(isLoading: true, messages: messages).messages)
        })
    }
}
let results: [String: Any] = ["checks": checks, "profile_activity_events_before": oldActivityUpdates.count, "profile_activity_events_after": newActivityUpdates.count, "tab_preparations_before": tabBaseline.preparations, "tab_preparations_after": tabCandidate.preparations, "checksum": checksum, "timings": timings]
if let path = ProcessInfo.processInfo.environment["PEER_MEDIA_RESULTS"] {
    try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
}
print("PASS: \(checks) checks")
