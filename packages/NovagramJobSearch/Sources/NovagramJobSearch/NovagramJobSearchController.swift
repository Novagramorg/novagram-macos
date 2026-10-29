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

private final class Arguments {
    let context: any AccountContextProtocol
    let setMode: (NovagramJobMode) -> Void
    let toggleCity: (String) -> Void
    let toggleFormat: (NovagramJobWorkFormat) -> Void
    let setPeriod: (NovagramJobPeriod) -> Void
    let toggleSalary: () -> Void
    let toggleSource: (NovagramJobSource) -> Void
    let searchGlobal: () -> Void
    let loadMore: () -> Void
    let openPost: (NovagramJobResult) -> Void
    let write: (NovagramJobResult) -> Void
    let copyContact: (NovagramJobResult) -> Void
    let findChannels: () -> Void
    let setWatched: (PeerId, Bool) -> Void
    let join: (PeerId) -> Void
    let openPeer: (PeerId) -> Void
    let saveCurrent: () -> Void
    let loadSaved: (NovagramJobSavedSearch) -> Void
    let toggleAlerts: (NovagramJobSavedSearch) -> Void
    let removeSaved: (NovagramJobSavedSearch) -> Void
    var toggleLanguage: (NovagramSearchLanguage?) -> Void = { _ in }

    init(context: any AccountContextProtocol, setMode: @escaping (NovagramJobMode) -> Void, toggleCity: @escaping (String) -> Void, toggleFormat: @escaping (NovagramJobWorkFormat) -> Void, setPeriod: @escaping (NovagramJobPeriod) -> Void, toggleSalary: @escaping () -> Void, toggleSource: @escaping (NovagramJobSource) -> Void, searchGlobal: @escaping () -> Void, loadMore: @escaping () -> Void, openPost: @escaping (NovagramJobResult) -> Void, write: @escaping (NovagramJobResult) -> Void, copyContact: @escaping (NovagramJobResult) -> Void, findChannels: @escaping () -> Void, setWatched: @escaping (PeerId, Bool) -> Void, join: @escaping (PeerId) -> Void, openPeer: @escaping (PeerId) -> Void, saveCurrent: @escaping () -> Void, loadSaved: @escaping (NovagramJobSavedSearch) -> Void, toggleAlerts: @escaping (NovagramJobSavedSearch) -> Void, removeSaved: @escaping (NovagramJobSavedSearch) -> Void) {
        self.context = context
        self.setMode = setMode
        self.toggleCity = toggleCity
        self.toggleFormat = toggleFormat
        self.setPeriod = setPeriod
        self.toggleSalary = toggleSalary
        self.toggleSource = toggleSource
        self.searchGlobal = searchGlobal
        self.loadMore = loadMore
        self.openPost = openPost
        self.write = write
        self.copyContact = copyContact
        self.findChannels = findChannels
        self.setWatched = setWatched
        self.join = join
        self.openPeer = openPeer
        self.saveCurrent = saveCurrent
        self.loadSaved = loadSaved
        self.toggleAlerts = toggleAlerts
        self.removeSaved = removeSaved
    }
}

private struct JobChannel: Equatable {
    let peer: EnginePeer
    let subscribers: Int32?
}

private struct JobChannelRowKey: Equatable {
    let channel: JobChannel
    let isWatched: Bool
    let isFirst: Bool
    let isLast: Bool
}

private struct State: Equatable {
    var filter: NovagramJobFilter
    var sources: NovagramJobSources = NovagramJobSources()
    var search: NovagramJobSearchState = NovagramJobSearchState()
    var watched: [JobChannel] = []
    var discovered: [JobChannel] = []
    var isDiscovering: Bool = false
    var saved: [NovagramJobSavedSearch] = []
    var isPremium: Bool = false
}

private let _id_query = InputDataIdentifier("_id_query")
private let _id_city = InputDataIdentifier("_id_city")
private let _id_format = InputDataIdentifier("_id_format")
private let _id_period = InputDataIdentifier("_id_period")
private let _id_salary = InputDataIdentifier("_id_salary")
private let _id_languages = InputDataIdentifier("_id_languages")
private let _id_global = InputDataIdentifier("_id_global")
private let _id_loading = InputDataIdentifier("_id_loading")
private let _id_load_more = InputDataIdentifier("_id_load_more")
private let _id_find_channels = InputDataIdentifier("_id_find_channels")
private let _id_save = InputDataIdentifier("_id_save")
private func _id_mode(_ mode: NovagramJobMode) -> InputDataIdentifier {
    return InputDataIdentifier("_id_mode_\(mode.rawValue)")
}
private func _id_source(_ source: NovagramJobSource) -> InputDataIdentifier {
    return InputDataIdentifier("_id_source_\(source.rawValue)")
}
private func _id_result(_ id: MessageId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_result_\(id.peerId.toInt64())_\(id.namespace)_\(id.id)")
}
private func _id_watched(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_watched_\(id.toInt64())")
}
private func _id_found(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_found_\(id.toInt64())")
}
private func _id_saved(_ id: String) -> InputDataIdentifier {
    return InputDataIdentifier("_id_saved_\(id)")
}

private func modeTitle(_ mode: NovagramJobMode) -> String {
    let strings = NovagramL10n.current
    switch mode {
    case .findJob:
        return strings.jobSearch_modeFindJob
    case .findCandidates:
        return strings.jobSearch_modeFindCandidates
    }
}

private func periodTitle(_ period: NovagramJobPeriod) -> String {
    let strings = NovagramL10n.current
    switch period {
    case .day:
        return strings.jobSearch_periodDay
    case .week:
        return strings.jobSearch_periodWeek
    case .month:
        return strings.jobSearch_periodMonth
    case .any:
        return strings.jobSearch_periodAny
    }
}

private func sourceTitle(_ source: NovagramJobSource) -> String {
    let strings = NovagramL10n.current
    switch source {
    case .hashtags:
        return strings.jobSearch_sourceHashtags
    case .myChats:
        return strings.jobSearch_sourceMyChats
    case .watched:
        return strings.jobSearch_sourceWatched
    case .global:
        return strings.jobSearch_sourceGlobal
    }
}

private func isSourceOn(_ source: NovagramJobSource, _ sources: NovagramJobSources) -> Bool {
    switch source {
    case .hashtags:
        return sources.hashtags
    case .myChats:
        return sources.myChats
    case .watched:
        return sources.watched
    case .global:
        return false
    }
}

private func globalDescription(_ state: State) -> String {
    let strings = NovagramL10n.current
    guard state.isPremium else {
        return strings.jobSearch_globalPremiumOnly
    }
    guard let quota = state.search.globalState else {
        return ""
    }
    if quota.remainingFreeSearches <= 0 {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let unlock = quota.unlockTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        return strings.jobSearch_globalResets(formatter.string(from: unlock))
    }
    return strings.jobSearch_globalQuota(Int(quota.remainingFreeSearches), Int(quota.totalFreeSearches))
}

private func canSearchGlobal(_ state: State) -> Bool {
    guard state.isPremium, !NovagramJobQuery.parse(state.filter.query).isEmpty else {
        return false
    }
    if let quota = state.search.globalState, quota.remainingFreeSearches <= 0 {
        return false
    }
    return true
}

private func filterEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    let language = appCurrentLanguage.languageCode
    var entries: [InputDataEntry] = []
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_filtersHeader.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let cityItems = NovagramJobPresets.cities.map { city -> ContextMenuItem in
        let item = ContextMenuItem(city.title(languageCode: language), handler: {
            arguments.toggleCity(city.id)
        })
        item.state = state.filter.cityIds.contains(city.id) ? .on : .off
        return item
    }
    let cityValue = NovagramJobPresets.cities.filter { state.filter.cityIds.contains($0.id) }.map { $0.title(languageCode: language) }.joined(separator: ", ")
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_city, data: .init(name: strings.jobSearch_city, color: theme.colors.text, type: .contextSelector(cityValue.isEmpty ? strings.jobSearch_any : cityValue, cityItems), viewType: .firstItem)))
    index += 1

    let formatItems = NovagramJobWorkFormat.allCases.map { format -> ContextMenuItem in
        let item = ContextMenuItem(novagramJobFormatTitle(format), handler: {
            arguments.toggleFormat(format)
        })
        item.state = state.filter.formats.contains(format) ? .on : .off
        return item
    }
    let formatValue = NovagramJobWorkFormat.allCases.filter { state.filter.formats.contains($0) }.map(novagramJobFormatTitle).joined(separator: ", ")
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_format, data: .init(name: strings.jobSearch_format, color: theme.colors.text, type: .contextSelector(formatValue.isEmpty ? strings.jobSearch_any : formatValue, formatItems), viewType: .innerItem)))
    index += 1

    let periodItems = NovagramJobPeriod.allCases.map { period -> ContextMenuItem in
        let item = ContextMenuItem(periodTitle(period), handler: {
            arguments.setPeriod(period)
        })
        item.state = state.filter.period == period ? .on : .off
        return item
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_period, data: .init(name: strings.jobSearch_period, color: theme.colors.text, type: .contextSelector(periodTitle(state.filter.period), periodItems), viewType: .innerItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_salary, data: .init(name: strings.jobSearch_onlySalary, color: theme.colors.text, type: .switchable(state.filter.onlyWithSalary), viewType: .innerItem, action: arguments.toggleSalary)))
    index += 1

    let noneItem = ContextMenuItem(strings.jobSearch_languagesNone, handler: {
        arguments.toggleLanguage(nil)
    })
    noneItem.state = state.filter.languages.isEmpty ? .on : .off
    let languageItems = [noneItem] + NovagramSearchLanguage.allCases.map { language -> ContextMenuItem in
        let item = ContextMenuItem(languageTitle(language), handler: {
            arguments.toggleLanguage(language)
        })
        item.state = state.filter.languages.contains(language) ? .on : .off
        return item
    }
    let languagesValue = NovagramSearchLanguage.allCases.filter { state.filter.languages.contains($0) }.map(languageTitle).joined(separator: ", ")
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_languages, data: .init(name: strings.jobSearch_languages, color: theme.colors.text, type: .contextSelector(languagesValue.isEmpty ? strings.jobSearch_languagesNone : languagesValue, languageItems), viewType: .lastItem)))
    index += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_languagesNote), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    return entries
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

private func sourceEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    var entries: [InputDataEntry] = []
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_sourcesHeader.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    let sources: [NovagramJobSource] = [.hashtags, .myChats, .watched]
    for (offset, source) in sources.enumerated() {
        let viewType: GeneralViewType = offset == 0 ? .firstItem : .innerItem
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_source(source), data: .init(name: sourceTitle(source), color: theme.colors.text, type: .switchable(isSourceOn(source, state.sources)), viewType: viewType, action: {
            arguments.toggleSource(source)
        })))
        index += 1
    }
    let enabled = canSearchGlobal(state)
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_global, data: .init(name: strings.jobSearch_globalSearch, color: enabled ? theme.colors.accent : theme.colors.grayText, type: state.search.isGlobalLoading ? .loading : .none, viewType: .lastItem, enabled: enabled, description: globalDescription(state), action: arguments.searchGlobal)))
    index += 1
    return entries
}

private func resultEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    let search = state.search
    var entries: [InputDataEntry] = []
    let header = search.items.isEmpty ? strings.jobSearch_resultsHeader : "\(strings.jobSearch_resultsHeader) (\(search.items.count))"
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(header.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    for source in [NovagramJobSource.hashtags, .myChats, .watched, .global] where search.failedSources.contains(source) {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_sourceFailed(sourceTitle(source))), data: .init(color: theme.colors.redUI, viewType: .textTopItem)))
        index += 1
    }
    if search.items.isEmpty {
        if search.isLoading {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: nil, comparable: nil, item: { initialSize, stableId in
                LoadingTableItem(initialSize, height: 60, stableId: stableId, viewType: .singleItem)
            }))
        } else {
            let text = search.hasRun ? strings.jobSearch_empty : strings.jobSearch_emptyQuery
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        }
        index += 1
        return entries
    }
    for (offset, result) in search.items.enumerated() {
        if offset > 0 {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_result(result.message.id), equatable: InputDataEquatable(result), comparable: nil, item: { initialSize, stableId in
            NovagramJobResultRowItem(initialSize, stableId: stableId, context: arguments.context, result: result, viewType: .singleItem, openPost: {
                arguments.openPost(result)
            }, write: {
                arguments.write(result)
            }, copyContact: {
                arguments.copyContact(result)
            })
        }))
        index += 1
    }
    if search.isLoading || search.canLoadMore {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_load_more, data: .init(name: strings.jobSearch_loadMore, color: theme.colors.accent, type: search.isLoading ? .loading : .none, viewType: .singleItem, enabled: !search.isLoading, action: arguments.loadMore)))
        index += 1
    }
    return entries
}

private func channelStatus(_ channel: JobChannel) -> String {
    var parts: [String] = []
    if let username = channel.peer.addressName, !username.isEmpty {
        parts.append("@" + username)
    }
    if let subscribers = channel.subscribers {
        let count = Int(subscribers)
        parts.append(strings().peerStatusSubscribersOther(count).replacingOccurrences(of: "\(count)", with: count.prettyNumber))
    }
    return parts.joined(separator: " · ")
}

private func channelEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    var entries: [InputDataEntry] = []
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_channelsHeader.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    let watchedIds = Set(state.watched.map { $0.peer.id })
    let rows = state.watched.map { ($0, true) } + state.discovered.filter { !watchedIds.contains($0.peer.id) }.map { ($0, false) }
    let total = rows.count + 1
    for (offset, row) in rows.enumerated() {
        let (channel, isWatched) = row
        let peerId = channel.peer.id
        var menu: [ContextMenuItem] = []
        if isWatched {
            menu.append(ContextMenuItem(strings.jobSearch_openPost, handler: { arguments.openPeer(peerId) }))
            menu.append(ContextMenuItem(strings.jobSearch_remove, handler: { arguments.setWatched(peerId, false) }))
        } else {
            menu.append(ContextMenuItem(strings.jobSearch_watch, handler: { arguments.setWatched(peerId, true) }))
            menu.append(ContextMenuItem(strings.jobSearch_openPost, handler: { arguments.openPeer(peerId) }))
            if case let .channel(value) = channel.peer, value.participationStatus != .member {
                menu.append(ContextMenuItem(strings.jobSearch_join, handler: { arguments.join(peerId) }))
            }
        }
        let viewType = bestGeneralViewType(Array(0 ..< total), for: offset)
        let status = channelStatus(channel)
        let key = JobChannelRowKey(channel: channel, isWatched: isWatched, isFirst: offset == 0, isLast: offset == total - 1)
        let items = menu
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: isWatched ? _id_watched(peerId) : _id_found(peerId), equatable: InputDataEquatable(key), comparable: nil, item: { initialSize, stableId in
            ShortPeerRowItem(initialSize, peer: channel.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, height: 50, photoSize: NSMakeSize(36, 36), status: status.isEmpty ? nil : status, inset: NSEdgeInsets(left: 20, right: 20), generalType: isWatched ? .context(strings.jobSearch_watching) : .none, viewType: viewType, action: {}, contextMenuItems: {
                .single(items)
            }, menuOnAction: true)
        }))
        index += 1
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_find_channels, data: .init(name: strings.jobSearch_findChannels, color: theme.colors.accent, type: state.isDiscovering ? .loading : .none, viewType: bestGeneralViewType(Array(0 ..< total), for: total - 1), action: arguments.findChannels)))
    index += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_channelsEmpty), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    return entries
}

private func savedEntries(_ state: State, arguments: Arguments, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    var entries: [InputDataEntry] = []
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_savedHeader.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    let total = state.saved.count + 1
    for (offset, saved) in state.saved.enumerated() {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_saved(saved.id), data: .init(name: saved.title, color: theme.colors.text, type: .switchable(saved.alertsEnabled), viewType: bestGeneralViewType(Array(0 ..< total), for: offset), description: saved.alertsEnabled ? strings.jobSearch_alertsOn : strings.jobSearch_alertsOff, action: {
            arguments.loadSaved(saved)
        }, switchAction: {
            arguments.toggleAlerts(saved)
        }, menuItems: {
            [ContextMenuItem(strings.jobSearch_remove, handler: { arguments.removeSaved(saved) })]
        }, autoswitch: false)))
        index += 1
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_save, data: .init(name: strings.jobSearch_saveCurrent, color: theme.colors.accent, viewType: bestGeneralViewType(Array(0 ..< total), for: total - 1), action: arguments.saveCurrent)))
    index += 1
    return entries
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    let strings = NovagramL10n.current
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    for (offset, mode) in NovagramJobMode.allCases.enumerated() {
        let viewType: GeneralViewType = offset == 0 ? .firstItem : .lastItem
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_mode(mode), data: .init(name: modeTitle(mode), color: theme.colors.text, type: .selectable(state.filter.mode == mode), viewType: viewType, action: {
            arguments.setMode(mode)
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_queryHeader.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.filter.query), error: nil, identifier: _id_query, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings.jobSearch_queryPlaceholder, filter: { $0 }, limit: 200))
    index += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings.jobSearch_queryHint), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries += filterEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries += sourceEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries += resultEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries += savedEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries += channelEntries(state, arguments: arguments, sectionId: &sectionId, index: &index)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    return entries
}

private func loadChannels(context: any AccountContextProtocol, ids: [Int64]) -> Signal<[JobChannel], NoError> {
    let peerIds = ids.map { PeerId($0) }.filter { !NovagramHiddenChatsManager.shared.isPeerHiddenInStorage($0) }
    let peers = EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })
    let counts = EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.ParticipantCount(id: $0) })
    return context.engine.data.get(peers, counts) |> map { peers, counts -> [JobChannel] in
        return peerIds.compactMap { peerId -> JobChannel? in
            guard let peer = peers[peerId] ?? nil else {
                return nil
            }
            let count = (counts[peerId] ?? nil).map { Int32(clamping: $0) }
            return JobChannel(peer: peer, subscribers: count)
        }
    }
}

private func discoverChannels(context: any AccountContextProtocol, query: NovagramJobQuery) -> Signal<[JobChannel], NoError> {
    let texts = NovagramJobChannelRelevance.discoveryQueries(userQuery: query.serverQueries.first)
    let signals = texts.map { text in
        NovagramJobRequestLimiter.shared.limited(context.engine.contacts.searchRemotePeers(query: text, scope: .channels) |> take(1)) |> map { $0.0 + $0.1 }
    }
    return combineLatest(signals) |> map { lists -> [JobChannel] in
        var seen = Set<PeerId>()
        var result: [JobChannel] = []
        for found in lists.flatMap({ $0 }) {
            guard case let .channel(channel) = found.peer else {
                continue
            }
            let peerId = found.peer.id
            guard seen.insert(peerId).inserted, !NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId), NovagramJobChannelRelevance.hasJobSignal(title: channel.title, username: found.peer.addressName) else {
                continue
            }
            result.append(JobChannel(peer: found.peer, subscribers: found.subscribers))
        }
        return result
    }
}

private func writeTarget(context: any AccountContextProtocol, result: NovagramJobResult) -> Signal<PeerId?, NoError> {
    for contact in result.info.contacts {
        if case let .username(value) = contact {
            let name = value.hasPrefix("@") ? String(value.dropFirst()) : value
            return context.engine.peers.resolvePeerByName(name: name, referrer: nil) |> mapToSignal { value -> Signal<PeerId?, NoError> in
                switch value {
                case .progress:
                    return .complete()
                case let .result(peer):
                    return .single(peer?.id)
                }
            } |> take(1)
        }
    }
    if let author = result.message.author as? TelegramUser {
        return .single(author.id)
    }
    return .single(nil)
}

public func NovagramJobSearchController(context: any AccountContextProtocol, savedSearchId: String? = nil) -> InputDataController {
    let actionsDisposable = DisposableSet()
    let discoverDisposable = MetaDisposable()
    actionsDisposable.add(discoverDisposable)
    let account = NovagramJobSearchEngine.account(context)
    let engine = NovagramJobSearchEngine(context: context)
    let savedFilter = savedSearchId.flatMap { id in NovagramJobStore.savedSearches(account: account).first(where: { $0.id == id })?.filter }
    let initialFilter = savedFilter ?? NovagramJobStore.lastFilter(account: account) ?? NovagramJobFilter()
    let initialState = State(filter: initialFilter, isPremium: context.isPremium)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> ViewController?)?
    var window: Window {
        return bestWindow(context, getController?())
    }

    NovagramJobAlertMonitor.shared.markSeen(account: account)
    let channelsDisposable = MetaDisposable()
    actionsDisposable.add(channelsDisposable)
    var loadedWatchedIds: [Int64]?

    let runSearch: () -> Void = {
        let state = stateValue.with { $0 }
        engine.update(filter: state.filter, sources: state.sources)
    }
    let updateFilter: ((inout NovagramJobFilter) -> Void) -> Void = { f in
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
    }
    let reloadStore: () -> Void = {
        updateState { current in
            var current = current
            current.saved = NovagramJobStore.savedSearches(account: account)
            return current
        }
        let watchedIds = NovagramJobStore.watchedChannels(account: account)
        guard watchedIds != loadedWatchedIds else {
            return
        }
        loadedWatchedIds = watchedIds
        channelsDisposable.set((loadChannels(context: context, ids: watchedIds) |> deliverOnMainQueue).start(next: { peers in
            updateState { current in
                var current = current
                current.watched = peers
                return current
            }
        }))
    }

    let arguments = Arguments(context: context, setMode: { mode in
        updateFilter { $0.mode = mode }
    }, toggleCity: { id in
        updateFilter { filter in
            if filter.cityIds.contains(id) {
                filter.cityIds.remove(id)
            } else {
                filter.cityIds.insert(id)
            }
        }
    }, toggleFormat: { format in
        updateFilter { filter in
            if filter.formats.contains(format) {
                filter.formats.remove(format)
            } else {
                filter.formats.insert(format)
            }
        }
    }, setPeriod: { period in
        updateFilter { $0.period = period }
    }, toggleSalary: {
        updateFilter { $0.onlyWithSalary.toggle() }
    }, toggleSource: { source in
        updateState { current in
            var current = current
            switch source {
            case .hashtags:
                current.sources.hashtags.toggle()
            case .myChats:
                current.sources.myChats.toggle()
            case .watched:
                current.sources.watched.toggle()
            case .global:
                break
            }
            return current
        }
        runSearch()
    }, searchGlobal: {
        engine.searchGlobalPosts()
    }, loadMore: {
        engine.loadMore()
    }, openPost: { result in
        NovagramJobSearchHooks.shared.openMessage(context, result.message.id)
    }, write: { result in
        actionsDisposable.add((writeTarget(context: context, result: result) |> deliverOnMainQueue).start(next: { peerId in
            if let peerId {
                NovagramJobSearchHooks.shared.openPeer(context, peerId)
            }
        }))
    }, copyContact: { result in
        guard let contact = result.info.contacts.first else {
            return
        }
        copyToClipboard(novagramJobContactText(contact))
        showModalText(for: window, text: NovagramL10n.current.jobSearch_copied)
    }, findChannels: {
        updateState { current in
            var current = current
            current.isDiscovering = true
            return current
        }
        let query = NovagramJobQuery.parse(stateValue.with { $0.filter.query })
        discoverDisposable.set((discoverChannels(context: context, query: query) |> deliverOnMainQueue).start(next: { peers in
            updateState { current in
                var current = current
                current.discovered = peers
                current.isDiscovering = false
                return current
            }
        }))
    }, setWatched: { peerId, watched in
        NovagramJobStore.setWatched(peerId.toInt64(), watched: watched, account: account)
        reloadStore()
        if stateValue.with({ $0.sources.watched }) {
            runSearch()
        }
    }, join: { peerId in
        actionsDisposable.add(context.engine.peers.joinChannel(peerId: peerId, hash: nil).start())
    }, openPeer: { peerId in
        NovagramJobSearchHooks.shared.openPeer(context, peerId)
    }, saveCurrent: {
        let filter = stateValue.with { $0.filter }
        let trimmed = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? modeTitle(filter.mode) : trimmed
        let saved = NovagramJobStore.savedSearches(account: account)
        if var existing = saved.first(where: { $0.filter == filter }) {
            existing.title = title
            NovagramJobStore.save(existing, account: account)
        } else if saved.count >= NovagramJobStore.maxSavedSearches {
            showModalText(for: window, text: NovagramL10n.current.jobSearch_savedLimit(NovagramJobStore.maxSavedSearches))
            return
        } else {
            NovagramJobStore.save(NovagramJobSavedSearch(title: title, filter: filter, lastSeenDate: NovagramJobSearchEngine.now()), account: account)
        }
        reloadStore()
    }, loadSaved: { saved in
        updateFilter { $0 = saved.filter }
    }, toggleAlerts: { saved in
        var updated = saved
        updated.alertsEnabled.toggle()
        if updated.alertsEnabled {
            updated.lastSeenDate = max(updated.lastSeenDate, NovagramJobSearchEngine.now())
        }
        NovagramJobStore.save(updated, account: account)
        reloadStore()
    }, removeSaved: { saved in
        NovagramJobStore.remove(id: saved.id, account: account)
        reloadStore()
    })
    arguments.toggleLanguage = { language in
        updateFilter { filter in
            guard let language else {
                filter.languages = []
                return
            }
            if filter.languages.contains(language) {
                filter.languages.remove(language)
            } else {
                filter.languages.insert(language)
            }
        }
    }

    actionsDisposable.add((engine.stateSignal |> deliverOnMainQueue).start(next: { search in
        updateState { current in
            var current = current
            current.search = search
            return current
        }
    }))

    let storeObserver = NotificationCenter.default.addObserver(forName: NovagramJobStore.didChangeNotification, object: nil, queue: .main, using: { _ in
        reloadStore()
    })

    let pageToken = NovagramJobAlertMonitor.shared.pageDidOpen(account: account, load: { searchId in
        guard let saved = NovagramJobStore.savedSearches(account: account).first(where: { $0.id == searchId }) else {
            return
        }
        NovagramJobAlertMonitor.shared.markSeen(account: account)
        updateFilter { $0 = saved.filter }
    })

    reloadStore()
    runSearch()

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: NovagramL10n.current.jobSearch_title, updateDatas: { data in
        let text = data[_id_query]?.stringValue ?? ""
        if text != stateValue.with({ $0.filter.query }) {
            updateFilter { $0.query = text }
        }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false)

    getController = { [weak controller] in
        return controller
    }

    controller.onDeinit = {
        NovagramJobAlertMonitor.shared.pageDidClose(token: pageToken)
        NotificationCenter.default.removeObserver(storeObserver)
        engine.cancel()
        actionsDisposable.dispose()
    }

    return controller
}
