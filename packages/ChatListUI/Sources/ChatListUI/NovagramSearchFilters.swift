import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import GeneralRows
import InputDataUI
import NovagramCore
import NovagramSearchKit

// Novagram extras on the global search (SearchController): hidden and locked chats stay out of the
// results, and the Messages section gets a date range plus "Unread only" / "Mentions only" filters
// in its "From:" dropdown.
struct NovagramSearchFilterState: Equatable {
    var stored = NovagramSearchKit.NovagramSearchFilterState()

    var active: NovagramSearchKit.NovagramSearchFilterState {
        return stored.effective(isFeaturesEnabled: NovagramSearchFeatures.isEnabled)
    }

    var hasDates: Bool {
        return active.hasDates
    }

    var filtersMessages: Bool {
        return active.filtersMessages
    }

    var unreadActive: Bool {
        return active.unreadOnly
    }

    var mentionsActive: Bool {
        return active.mentionsOnly
    }

    var isActive: Bool {
        return active.isActive
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
    let active = filter.active
    return messages.filter { message in
        if privacy.hidesMessage(message) {
            return false
        }
        guard active.filtersMessages else {
            return true
        }
        return active.keeps(isUnread: novagramIsUnread(message, readStates: readStates), mentionsAccount: novagramMentionsMe(message))
    }
}

private func novagramIsUnread(_ message: Message, readStates: [PeerId: CombinedPeerReadState]) -> Bool {
    let isRead = readStates[message.id.peerId].map { $0.isIncomingMessageIndexRead(message.index) }
    return NovagramSearchKit.NovagramSearchFilterState.isUnread(isIncoming: message.flags.contains(.Incoming), isRead: isRead)
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
typealias NovagramSearchPage = (SearchMessagesResult, SearchMessagesState)

typealias NovagramFilterAutoLoad = NovagramSearchAutoLoad

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
    func step(_ value: NovagramSearchPage, load: NovagramFilledLoad<MessageId>) -> Signal<NovagramSearchPage, NoError> {
        var load = load
        let keptIds = Set(novagramSearchKeptMessages(value.0.messages, readStates: value.0.readStates, filter: filter).map { $0.id })
        guard load.add(page: value.0.messages, id: { $0.id }, completed: value.0.completed, isKept: { keptIds.contains($0.id) }) else {
            autoLoad.finishLoad(matched: load.matched, completed: value.0.completed)
            return .single(value)
        }
        let nextLoad = load
        let more = next(value.1)
            |> take(1)
            |> mapToSignal { step($0, load: nextLoad) }
        return .single(value) |> then(more)
    }
    let load = NovagramFilledLoad<MessageId>(previousIds: Set((previous ?? []).map { $0.id }))
    return first |> mapToSignal { step($0, load: load) }
}

func novagramWithReadStates(
    _ signal: Signal<NovagramSearchPage, NoError>,
    postbox: Postbox,
    filter: NovagramSearchFilterState
) -> Signal<NovagramSearchPage, NoError> {
    guard filter.unreadActive else {
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
            return .general(scope: scope, groupId: groupId, tags: tags, minDate: filter.active.minDate, maxDate: filter.active.maxDate, folderId: folderId, communityId: communityId)
        case let .peer(peerId, fromId, tags, reactions, threadId, _, _):
            return .peer(peerId: peerId, fromId: fromId, tags: tags, reactions: reactions, threadId: threadId, minDate: filter.active.minDate, maxDate: filter.active.maxDate)
        default:
            return self
        }
    }
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
    for part in filter.active.titleParts {
        switch part {
        case let .dates(from, to):
            parts.append(novagramShortDate(from) + "–" + novagramShortDate(to))
        case let .from(from):
            parts.append(novagramShortDate(from) + "–…")
        case let .to(to):
            parts.append("…–" + novagramShortDate(to))
        case .unreadOnly:
            parts.append(l10n.search_unreadOnly)
        case .mentionsOnly:
            parts.append(l10n.search_mentionsOnly)
        }
    }
    return parts.joined(separator: " · ")
}

func novagramSearchFilterActions(_ filter: NovagramSearchFilterState, window: Window, update: @escaping (NovagramSearchFilterState) -> Void) -> [SeparatorBlockState.DropdownAction] {
    guard NovagramSearchFeatures.isEnabled else {
        return []
    }
    let l10n = NovagramL10n.current
    var actions: [SeparatorBlockState.DropdownAction] = []
    let stored = filter.stored
    actions.append(.init(title: stored.minDate.map { l10n.search_fromDateValue(novagramShortDate($0)) } ?? l10n.search_fromDate, selected: stored.minDate != nil, action: {
        novagramPickDate(window: window, current: stored.minDate, done: { date in
            var updated = filter
            updated.stored.setFromDay(date)
            update(updated)
        })
    }))
    actions.append(.init(title: stored.maxDate.map { l10n.search_toDateValue(novagramShortDate($0)) } ?? l10n.search_toDate, selected: stored.maxDate != nil, action: {
        novagramPickDate(window: window, current: stored.maxDate, done: { date in
            var updated = filter
            updated.stored.setToDay(date)
            update(updated)
        })
    }))
    if filter.hasDates {
        actions.append(.init(title: l10n.search_clearDates, selected: false, action: {
            var updated = filter
            updated.stored.clearDates()
            update(updated)
        }))
    }
    actions.append(.init(title: l10n.search_unreadOnly, selected: stored.unreadOnly, action: {
        var updated = filter
        updated.stored.unreadOnly.toggle()
        update(updated)
    }))
    actions.append(.init(title: l10n.search_mentionsOnly, selected: stored.mentionsOnly, action: {
        var updated = filter
        updated.stored.mentionsOnly.toggle()
        update(updated)
    }))
    return actions
}
