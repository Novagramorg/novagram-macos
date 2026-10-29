import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import GeneralRows
import InputDataUI
import NovagramCore

// Novagram extras on the global search (SearchController): hidden and locked chats stay out of the
// results, and the Messages section gets a date range plus "Unread only" / "Mentions only" filters
// in its "From:" dropdown.
struct NovagramSearchFilterState: Equatable {
    var minDate: Int32?
    var maxDate: Int32?
    var unreadOnly = false
    var mentionsOnly = false

    var hasDates: Bool {
        return minDate != nil || maxDate != nil
    }

    var filtersMessages: Bool {
        return unreadOnly || mentionsOnly
    }

    var isActive: Bool {
        return hasDates || filtersMessages
    }
}

// MARK: - Privacy

// A hidden chat (Novagram Hidden Chats) never shows in search, even while hidden chats are revealed.
func novagramSearchHides(_ peerId: PeerId) -> Bool {
    return NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId)
}

func novagramSearchHides(_ rendered: RenderedPeer) -> Bool {
    if novagramSearchHides(rendered.peerId) {
        return true
    }
    if let main = rendered.chatMainPeer, novagramSearchHides(main.id) {
        return true
    }
    return false
}

// Message results also skip chats locked with Chat Lock: the lock guards the content, while the chat
// name may still show (as in the chat list).
func novagramSearchPrivateMessages(_ messages: [Message]) -> [Message] {
    return NovagramSearchPrivacy.kept(messages, message: { $0 })
}

// MARK: - Message filters

func novagramSearchKeptMessages(_ messages: [Message], readStates: [PeerId: CombinedPeerReadState], filter: NovagramSearchFilterState) -> [Message] {
    let privacy = NovagramSearchPrivacyPass()
    return messages.filter { message in
        if privacy.hidesMessage(message) {
            return false
        }
        if filter.unreadOnly && !novagramIsUnread(message, readStates: readStates) {
            return false
        }
        if filter.mentionsOnly && !novagramMentionsMe(message) {
            return false
        }
        return true
    }
}

private func novagramIsUnread(_ message: Message, readStates: [PeerId: CombinedPeerReadState]) -> Bool {
    guard message.flags.contains(.Incoming), let readState = readStates[message.id.peerId] else {
        return false
    }
    return !readState.isIncomingMessageIndexRead(message.index)
}

// The server marks a message that mentions the account with ConsumablePersonalMentionMessageAttribute.
private func novagramMentionsMe(_ message: Message) -> Bool {
    if message.tags.contains(.unseenPersonalMessage) {
        return true
    }
    return message.attributes.contains(where: { $0 is ConsumablePersonalMentionMessageAttribute })
}

// "Unread only" / "Mentions only" drop most of a page: keep reading the next pages until enough
// messages pass or a few more pages were read, so the list does not stop short.
private let novagramFilledResultCount = 20
private let novagramExtraPages = 5

typealias NovagramSearchPage = (SearchMessagesResult, SearchMessagesState)

final class NovagramFilterAutoLoad {
    private struct State {
        var shown = 0
        var autoLoads = 0
        var pending = false
    }

    private static let maxAutoLoads = 3
    private let state = Atomic(value: State())

    fileprivate func startLoad(fresh: Bool) {
        _ = state.modify { current in
            var current = current
            if fresh {
                current = State()
            }
            current.pending = false
            return current
        }
    }

    fileprivate func finishLoad(matched: Int, completed: Bool) {
        _ = state.modify { current in
            var current = current
            current.shown += matched
            let short = current.shown < novagramFilledResultCount
            current.pending = short && !completed && current.autoLoads < NovagramFilterAutoLoad.maxAutoLoads
            return current
        }
    }

    func takeRequest() -> Bool {
        var take = false
        _ = state.modify { current in
            var current = current
            if current.pending {
                current.pending = false
                current.autoLoads += 1
                take = true
            }
            return current
        }
        return take
    }
}

func novagramFillFilteredPage(
    _ first: Signal<NovagramSearchPage, NoError>,
    filter: NovagramSearchFilterState,
    previous: [Message]?,
    autoLoad: NovagramFilterAutoLoad,
    next: @escaping (SearchMessagesState) -> Signal<NovagramSearchPage, NoError>
) -> Signal<NovagramSearchPage, NoError> {
    guard filter.filtersMessages else {
        return first
    }
    autoLoad.startLoad(fresh: previous == nil)
    func step(
        _ value: NovagramSearchPage,
        seen: Set<MessageId>,
        matched: Int,
        pagesLeft: Int
    ) -> Signal<NovagramSearchPage, NoError> {
        let added = value.0.messages.filter { !seen.contains($0.id) }
        let matched = matched + novagramSearchKeptMessages(added, readStates: value.0.readStates, filter: filter).count
        if pagesLeft == 0 || value.0.completed || matched >= novagramFilledResultCount {
            autoLoad.finishLoad(matched: matched, completed: value.0.completed)
            return .single(value)
        }
        let seenNow = Set(value.0.messages.map { $0.id })
        let more = next(value.1)
            |> take(1)
            |> mapToSignal { step($0, seen: seenNow, matched: matched, pagesLeft: pagesLeft - 1) }
        return .single(value) |> then(more)
    }
    let seen = Set((previous ?? []).map { $0.id })
    return first |> mapToSignal { step($0, seen: seen, matched: 0, pagesLeft: novagramExtraPages) }
}

func novagramWithReadStates(
    _ signal: Signal<NovagramSearchPage, NoError>,
    postbox: Postbox,
    filter: NovagramSearchFilterState
) -> Signal<NovagramSearchPage, NoError> {
    guard filter.unreadOnly else {
        return signal
    }
    return signal |> mapToSignal { value -> Signal<NovagramSearchPage, NoError> in
        let known = value.0.readStates
        let missing = Set(value.0.messages.map { $0.id.peerId }).filter { known[$0] == nil }
        if missing.isEmpty {
            return .single(value)
        }
        return postbox.transaction { transaction -> NovagramSearchPage in
            var readStates = known
            for peerId in missing {
                if let readState = transaction.getCombinedPeerReadState(peerId) {
                    readStates[peerId] = readState
                }
            }
            let result = value.0
            let merged = SearchMessagesResult(
                messages: result.messages,
                readStates: readStates,
                threadInfo: result.threadInfo,
                totalCount: result.totalCount,
                completed: result.completed
            )
            return (merged, value.1)
        }
    }
}

// MARK: - Dates

extension SearchMessagesLocation {
    func novagramDates(_ filter: NovagramSearchFilterState) -> SearchMessagesLocation {
        guard filter.hasDates else {
            return self
        }
        switch self {
        case let .general(scope, groupId, tags, _, _, folderId, communityId):
            return .general(scope: scope, groupId: groupId, tags: tags, minDate: filter.minDate, maxDate: filter.maxDate, folderId: folderId, communityId: communityId)
        case let .peer(peerId, fromId, tags, reactions, threadId, _, _):
            return .peer(peerId: peerId, fromId: fromId, tags: tags, reactions: reactions, threadId: threadId, minDate: filter.minDate, maxDate: filter.maxDate)
        default:
            return self
        }
    }
}

private func novagramDayStart(_ date: Date) -> Int32 {
    return Int32(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
}

// The "To" day is included: the range ends one second before the next day starts.
private func novagramDayEnd(_ date: Date) -> Int32 {
    let start = Calendar.current.startOfDay(for: date)
    let next = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
    return Int32(next.timeIntervalSince1970) - 1
}

private func novagramShortDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

private func novagramPickDate(window: Window, current: Int32?, done: @escaping (Date) -> Void) {
    let start = current.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
    guard let controller = FeatureNavigationHooks.shared.makeCalendarController(window, start, 2013, false, done) else {
        return
    }
    let navigation = NavigationViewController(controller, window)
    navigation._frameRect = NSMakeRect(0, 0, 300, 330)
    showModal(with: navigation, for: window)
}

// MARK: - Dropdown

// The section header shows the active filters after Telegram's "From: …" text, so the row redraws
// whenever a filter changes (DropdownAction equality only compares titles).
func novagramSearchFilterTitle(_ base: String, _ filter: NovagramSearchFilterState) -> String {
    let l10n = NovagramL10n.current
    var parts = [base]
    if filter.hasDates {
        parts.append((filter.minDate.map(novagramShortDate) ?? "…") + "–" + (filter.maxDate.map(novagramShortDate) ?? "…"))
    }
    if filter.unreadOnly {
        parts.append(l10n.search_unreadOnly)
    }
    if filter.mentionsOnly {
        parts.append(l10n.search_mentionsOnly)
    }
    return parts.joined(separator: " · ")
}

func novagramSearchFilterActions(_ filter: NovagramSearchFilterState, window: Window, update: @escaping (NovagramSearchFilterState) -> Void) -> [SeparatorBlockState.DropdownAction] {
    let l10n = NovagramL10n.current
    var actions: [SeparatorBlockState.DropdownAction] = []
    actions.append(.init(title: filter.minDate.map { l10n.search_fromDateValue(novagramShortDate($0)) } ?? l10n.search_fromDate, selected: filter.minDate != nil, action: {
        novagramPickDate(window: window, current: filter.minDate, done: { date in
            var updated = filter
            updated.minDate = novagramDayStart(date)
            update(updated)
        })
    }))
    actions.append(.init(title: filter.maxDate.map { l10n.search_toDateValue(novagramShortDate($0)) } ?? l10n.search_toDate, selected: filter.maxDate != nil, action: {
        novagramPickDate(window: window, current: filter.maxDate, done: { date in
            var updated = filter
            updated.maxDate = novagramDayEnd(date)
            update(updated)
        })
    }))
    if filter.hasDates {
        actions.append(.init(title: l10n.search_clearDates, selected: false, action: {
            var updated = filter
            updated.minDate = nil
            updated.maxDate = nil
            update(updated)
        }))
    }
    actions.append(.init(title: l10n.search_unreadOnly, selected: filter.unreadOnly, action: {
        var updated = filter
        updated.unreadOnly.toggle()
        update(updated)
    }))
    actions.append(.init(title: l10n.search_mentionsOnly, selected: filter.mentionsOnly, action: {
        var updated = filter
        updated.mentionsOnly.toggle()
        update(updated)
    }))
    return actions
}
