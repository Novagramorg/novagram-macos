import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import InputDataUI
import GeneralRows
import ShortPeerRow
import NovagramCore
import NovagramSearchKit

private final class Arguments {
    let context: any AccountContextProtocol
    let updateFilter: ((inout NovagramSuperSearchFilter) -> Void) -> Void
    let searchGlobal: () -> Void
    let loadMore: (NovagramSuperSearchSource) -> Void
    let openItem: (NovagramSuperSearchItem) -> Void
    let openPeer: (PeerId) -> Void

    init(context: any AccountContextProtocol, updateFilter: @escaping ((inout NovagramSuperSearchFilter) -> Void) -> Void, searchGlobal: @escaping () -> Void, loadMore: @escaping (NovagramSuperSearchSource) -> Void, openItem: @escaping (NovagramSuperSearchItem) -> Void, openPeer: @escaping (PeerId) -> Void) {
        self.context = context
        self.updateFilter = updateFilter
        self.searchGlobal = searchGlobal
        self.loadMore = loadMore
        self.openItem = openItem
        self.openPeer = openPeer
    }
}

private struct State: Equatable {
    var query: String = ""
    var filter = NovagramSuperSearchFilter()
    var search = NovagramSuperSearchState()
    var isPremium: Bool = false
}

private struct PeerRowKey: Equatable {
    let peer: NovagramSuperSearchPeer
    let viewType: GeneralViewType
}

private let _id_query = InputDataIdentifier("_id_query")
private let _id_period = InputDataIdentifier("_id_period")
private let _id_chat_kinds = InputDataIdentifier("_id_chat_kinds")
private let _id_media_kinds = InputDataIdentifier("_id_media_kinds")
private let _id_hide_spam = InputDataIdentifier("_id_hide_spam")
private let _id_languages = InputDataIdentifier("_id_languages")
private let _id_global = InputDataIdentifier("_id_global")
private let _id_loading = InputDataIdentifier("_id_loading")
private func _id_source(_ source: NovagramSuperSearchSource) -> InputDataIdentifier {
    return InputDataIdentifier("_id_source_\(source.rawValue)")
}
private func _id_load_more(_ source: NovagramSuperSearchSource) -> InputDataIdentifier {
    return InputDataIdentifier("_id_load_more_\(source.rawValue)")
}
private func _id_result(_ id: NovagramSuperSearchHitId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_result_\(id.peerId)_\(id.namespace)_\(id.id)")
}
private func _id_peer(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_\(id.toInt64())")
}

private let switchSources: [NovagramSuperSearchSource] = [.myChats, .publicChats, .publicChannelPosts, .hashtagPosts, .archive]
private let resultSources: [NovagramSuperSearchSource] = [.myChats, .publicChats, .publicChannelPosts, .hashtagPosts, .globalPosts, .archive]

func novagramSuperSearchSourceTitle(_ source: NovagramSuperSearchSource) -> String {
    let strings = NovagramL10n.current
    switch source {
    case .myChats:
        return strings.superSearch_sourceMyChats
    case .publicChats:
        return strings.superSearch_sourcePublicChats
    case .publicChannelPosts:
        return strings.superSearch_sourceChannelPosts
    case .hashtagPosts:
        return strings.superSearch_sourceHashtags
    case .globalPosts:
        return strings.superSearch_sourceGlobal
    case .archive:
        return strings.superSearch_sourceArchive
    }
}

func novagramSuperSearchMediaTitle(_ kind: NovagramSuperSearchMediaKind) -> String {
    let strings = NovagramL10n.current
    switch kind {
    case .text:
        return strings.superSearch_mediaText
    case .photo:
        return strings.superSearch_mediaPhoto
    case .video:
        return strings.superSearch_mediaVideo
    case .file:
        return strings.superSearch_mediaFile
    case .link:
        return strings.superSearch_mediaLink
    case .voice:
        return strings.superSearch_mediaVoice
    case .music:
        return strings.superSearch_mediaMusic
    }
}

private func periodTitle(_ period: NovagramSuperSearchPeriod) -> String {
    let strings = NovagramL10n.current
    switch period {
    case .day:
        return strings.superSearch_periodDay
    case .week:
        return strings.superSearch_periodWeek
    case .month:
        return strings.superSearch_periodMonth
    case .year:
        return strings.superSearch_periodYear
    case .any:
        return strings.superSearch_periodAny
    }
}

private func chatKindTitle(_ kind: NovagramSuperSearchChatKind) -> String {
    let strings = NovagramL10n.current
    switch kind {
    case .privateChat:
        return strings.superSearch_chatPrivate
    case .group:
        return strings.superSearch_chatGroup
    case .channel:
        return strings.superSearch_chatChannel
    case .bot:
        return strings.superSearch_chatBot
    }
}

private func languageTitle(_ language: NovagramSearchLanguage) -> String {
    switch language {
    case .uzLatin:
        return "O'zbekcha (lotin)"
    case .uzCyrillic:
        return "Ўзбекча (кирилл)"
    case .russian:
        return "Русский"
    case .english:
        return "English"
    }
}

private func toggled<Value: Hashable>(_ set: Set<Value>, _ value: Value) -> Set<Value> {
    var result = set
    if result.contains(value) {
        result.remove(value)
    } else {
        result.insert(value)
    }
    return result
}

private func multiSelector<Value: Hashable>(_ all: [Value], selected: Set<Value>, allTitle: String, title: (Value) -> String, select: @escaping (Value?) -> Void) -> (String, [ContextMenuItem]) {
    let allItem = ContextMenuItem(allTitle, handler: {
        select(nil)
    })
    allItem.state = selected.isEmpty ? .on : .off
    let items = [allItem] + all.map { value -> ContextMenuItem in
        let item = ContextMenuItem(title(value), handler: {
            select(value)
        })
        item.state = selected.contains(value) ? .on : .off
        return item
    }
    let value = all.filter(selected.contains).map(title).joined(separator: ", ")
    return (value.isEmpty ? allTitle : value, items)
}

private func filterEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    let filter = state.filter
    var entries: [InputDataEntry] = []
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.superSearch_filtersHeader.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let periodItems = NovagramSuperSearchPeriod.allCases.reversed().map { period -> ContextMenuItem in
        let item = ContextMenuItem(periodTitle(period), handler: {
            arguments.updateFilter { $0.period = period }
        })
        item.state = filter.period == period ? .on : .off
        return item
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_period, data: .init(name: strings.superSearch_period, color: theme.colors.text, type: .contextSelector(periodTitle(filter.period), periodItems), viewType: .firstItem)))
    index += 1

    let chatKinds = multiSelector(NovagramSuperSearchChatKind.allCases, selected: filter.chatKinds, allTitle: strings.superSearch_all, title: chatKindTitle, select: { kind in
        arguments.updateFilter { filter in filter.chatKinds = kind.map { toggled(filter.chatKinds, $0) } ?? [] }
    })
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_chat_kinds, data: .init(name: strings.superSearch_chatKinds, color: theme.colors.text, type: .contextSelector(chatKinds.0, chatKinds.1), viewType: .innerItem)))
    index += 1

    let mediaKinds = multiSelector(NovagramSuperSearchMediaKind.allCases, selected: filter.mediaKinds, allTitle: strings.superSearch_all, title: novagramSuperSearchMediaTitle, select: { kind in
        arguments.updateFilter { filter in filter.mediaKinds = kind.map { toggled(filter.mediaKinds, $0) } ?? [] }
    })
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_media_kinds, data: .init(name: strings.superSearch_mediaKinds, color: theme.colors.text, type: .contextSelector(mediaKinds.0, mediaKinds.1), viewType: .innerItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_hide_spam, data: .init(name: strings.superSearch_hideSpam, color: theme.colors.text, type: .switchable(filter.hideSpam), viewType: .innerItem, action: {
        arguments.updateFilter { $0.hideSpam.toggle() }
    })))
    index += 1

    let languages = multiSelector(NovagramSearchLanguage.allCases, selected: filter.languages, allTitle: strings.superSearch_languagesNone, title: languageTitle, select: { language in
        arguments.updateFilter { filter in filter.languages = language.map { toggled(filter.languages, $0) } ?? [] }
    })
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_languages, data: .init(name: strings.superSearch_languages, color: theme.colors.text, type: .contextSelector(languages.0, languages.1), viewType: .lastItem)))
    index += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.superSearch_languagesNote), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    return entries
}

private func sourceDescription(_ status: NovagramSuperSearchSourceStatus, title: String, hasRun: Bool) -> String? {
    let strings = NovagramL10n.current
    if status.isLoading {
        return strings.superSearch_searching
    }
    if status.failed {
        return strings.superSearch_sourceFailed(title)
    }
    return hasRun ? strings.superSearch_found(status.count) : nil
}

private func globalDescription(_ state: State) -> String {
    let strings = NovagramL10n.current
    guard state.isPremium else {
        return strings.superSearch_globalPremiumOnly
    }
    guard let quota = state.search.globalState else {
        return ""
    }
    if quota.remainingFreeSearches <= 0 {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let unlock = quota.unlockTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        return strings.superSearch_globalResets(formatter.string(from: unlock))
    }
    return strings.superSearch_globalQuota(Int(quota.remainingFreeSearches), Int(quota.totalFreeSearches))
}

private func canSearchGlobal(_ state: State) -> Bool {
    guard state.isPremium, state.search.hasRun, !state.search.status(.globalPosts).isLoading else {
        return false
    }
    if let quota = state.search.globalState, quota.remainingFreeSearches <= 0 {
        return false
    }
    return true
}

private func sourceEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    var entries: [InputDataEntry] = []
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.superSearch_sourcesHeader.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    for (offset, source) in switchSources.enumerated() {
        let isOn = state.filter.sources.contains(source)
        let description = isOn ? sourceDescription(state.search.status(source), title: novagramSuperSearchSourceTitle(source), hasRun: state.search.hasRun) : nil
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_source(source), data: .init(name: novagramSuperSearchSourceTitle(source), color: theme.colors.text, type: .switchable(isOn), viewType: offset == 0 ? .firstItem : .innerItem, description: description, descTextColor: theme.colors.grayText, action: {
            arguments.updateFilter { $0.sources = toggled($0.sources, source) }
        })))
        index += 1
    }
    let enabled = canSearchGlobal(state)
    let global = state.search.status(.globalPosts)
    let globalText = [global.failed ? strings.superSearch_sourceFailed(strings.superSearch_sourceGlobal) : nil, global.count > 0 ? strings.superSearch_found(global.count) : nil, globalDescription(state)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_global, data: .init(name: strings.superSearch_globalSearch, color: enabled ? theme.colors.accent : theme.colors.text.withAlphaComponent(0.5), type: global.isLoading ? .loading : .none, viewType: .lastItem, enabled: enabled, description: globalText, descTextColor: theme.colors.grayText, action: arguments.searchGlobal)))
    index += 1
    return entries
}

private func peerStatus(_ item: NovagramSuperSearchPeer) -> String? {
    var parts: [String] = []
    if let username = item.peer.addressName, !username.isEmpty {
        parts.append("@" + username)
    }
    if let subscribers = item.subscribers {
        let count = Int(subscribers)
        parts.append(strings().peerStatusSubscribersOther(count).replacingOccurrences(of: "\(count)", with: count.prettyNumber))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

private func peerEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let peers = state.search.peers
    guard !peers.isEmpty else {
        return []
    }
    var entries: [InputDataEntry] = []
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("\(NovagramL10n.current.superSearch_peersHeader) (\(peers.count))".uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    for (offset, item) in peers.enumerated() {
        let viewType = bestGeneralViewType(Array(0 ..< peers.count), for: offset)
        let peerId = item.peer.id
        let status = peerStatus(item)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(peerId), equatable: InputDataEquatable(PeerRowKey(peer: item, viewType: viewType)), comparable: nil, item: { initialSize, stableId in
            ShortPeerRowItem(initialSize, peer: item.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, height: 50, photoSize: NSSize(width: 36, height: 36), status: status, inset: NSEdgeInsets(left: 20, right: 20), viewType: viewType, action: {
                arguments.openPeer(peerId)
            })
        }))
        index += 1
    }
    return entries
}

private func messageEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    let search = state.search
    var entries: [InputDataEntry] = []
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    let header = search.items.isEmpty ? strings.superSearch_messagesHeader : "\(strings.superSearch_messagesHeader) (\(search.items.count))"
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(header.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    for source in resultSources where search.status(source).failed && (state.filter.sources.contains(source) || source == .globalPosts) {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.superSearch_sourceFailed(novagramSuperSearchSourceTitle(source))), data: .init(color: theme.colors.redUI, viewType: .textTopItem)))
        index += 1
    }
    if search.items.isEmpty {
        if search.isLoading {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: nil, comparable: nil, item: { initialSize, stableId in
                LoadingTableItem(initialSize, height: 60, stableId: stableId, viewType: .singleItem)
            }))
        } else {
            let text = search.hasQuery && search.hasRun ? strings.superSearch_empty : strings.superSearch_emptyQuery
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        }
        index += 1
    }
    let moreSources = resultSources.filter { source in
        let status = search.status(source)
        return (state.filter.sources.contains(source) || source == .globalPosts) && source != .publicChats && (status.canLoadMore || (status.isLoading && search.status(source).count > 0))
    }
    let total = search.items.count + moreSources.count
    for (offset, item) in search.items.enumerated() {
        let viewType = bestGeneralViewType(Array(0 ..< total), for: offset)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_result(item.hit.id), equatable: InputDataEquatable(InputDataEquatableValue(item: item, viewType: viewType)), comparable: nil, item: { initialSize, stableId in
            NovagramSuperSearchResultRowItem(initialSize, stableId: stableId, context: arguments.context, item: item, viewType: viewType, open: {
                arguments.openItem(item)
            })
        }))
        index += 1
    }
    for (offset, source) in moreSources.enumerated() {
        let status = search.status(source)
        let viewType = bestGeneralViewType(Array(0 ..< total), for: search.items.count + offset)
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_load_more(source), data: .init(name: strings.superSearch_loadMore(novagramSuperSearchSourceTitle(source)), color: theme.colors.accent, type: status.isLoading ? .loading : .none, viewType: viewType, enabled: !status.isLoading, action: {
            arguments.loadMore(source)
        })))
        index += 1
    }
    return entries
}

private struct InputDataEquatableValue: Equatable {
    let item: NovagramSuperSearchItem
    let viewType: GeneralViewType
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.query), error: nil, identifier: _id_query, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings.superSearch_queryPlaceholder, filter: { $0 }, limit: 200))
    index += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.superSearch_queryHint), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries += filterEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries += sourceEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries += peerEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)
    entries += messageEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    return entries
}

public func NovagramSuperSearchController(context: any AccountContextProtocol) -> InputDataController {
    let actionsDisposable = DisposableSet()
    let engine = NovagramSuperSearchEngine(context: context)
    let initialState = State(isPremium: context.isPremium)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let runSearch: () -> Void = {
        let state = stateValue.with { $0 }
        engine.update(query: state.query, filter: state.filter)
    }

    let arguments = Arguments(context: context, updateFilter: { f in
        var changed = false
        updateState { current in
            var current = current
            let previous = current.filter
            f(&current.filter)
            changed = previous != current.filter
            return current
        }
        if changed {
            runSearch()
        }
    }, searchGlobal: {
        updateState { current in
            var current = current
            current.filter.sources.insert(.globalPosts)
            return current
        }
        runSearch()
        engine.searchGlobalPosts()
    }, loadMore: { source in
        engine.loadMore(source)
    }, openItem: { item in
        if let message = item.message {
            NovagramSuperSearchHooks.shared.openMessage(context, message)
        } else if item.isDeleted {
            NovagramSuperSearchHooks.shared.openPeer(context, item.messageId.peerId)
        } else {
            NovagramSuperSearchHooks.shared.openMessageId(context, item.messageId)
        }
    }, openPeer: { peerId in
        NovagramSuperSearchHooks.shared.openPeer(context, peerId)
    })

    actionsDisposable.add((engine.stateSignal |> deliverOnMainQueue).start(next: { search in
        updateState { current in
            var current = current
            current.search = search
            return current
        }
    }))

    runSearch()

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: NovagramL10n.current.superSearch_title, updateDatas: { data in
        let text = data[_id_query]?.stringValue ?? ""
        if text != stateValue.with({ $0.query }) {
            updateState { current in
                var current = current
                current.query = text
                return current
            }
            runSearch()
        }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false)

    controller.onDeinit = {
        engine.cancel()
        actionsDisposable.dispose()
    }

    return controller
}
