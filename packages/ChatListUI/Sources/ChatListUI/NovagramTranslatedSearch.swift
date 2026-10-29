import Cocoa
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import NovagramCore

struct NovagramTranslatedMessages {
    let text: String
    let messages: [Message]
    let readStates: [PeerId: CombinedPeerReadState]
    let threadInfo: [MessageId: MessageHistoryThreadData]

    var title: String {
        return NovagramL10n.current.search_translatedTitle(text)
    }
}

struct NovagramTranslatedScope {
    let query: String
    let target: SearchControllerTarget
    let tags: SearchTags
    let options: AppSearchOptions

    var applies: Bool {
        guard target.isCommon, options.contains(.messages), tags.isEmpty else {
            return false
        }
        return !query.hasPrefix("#") && !query.hasPrefix("$")
    }
}

private let novagramTranslatedLimit = 20

func novagramTranslatedSearch(
    _ context: any AccountContextProtocol,
    scope: NovagramTranslatedScope,
    location: SearchMessagesLocation,
    source: Signal<SearchControllerMessaagesSourceValue, NoError>,
    filter: Signal<NovagramSearchFilterState, NoError>
) -> Signal<NovagramTranslatedMessages?, NoError> {
    guard scope.applies, NovagramQueryTranslator.isEnabled else {
        return .single(nil)
    }
    let engine = context.engine
    let translation = NovagramQueryTranslator.translatedQuery(engine: engine, query: scope.query)
    let translated: Signal<NovagramTranslatedMessages?, NoError> = translation
        |> mapToSignal { text -> Signal<NovagramTranslatedMessages?, NoError> in
            guard let text else {
                return .single(nil)
            }
            return combineLatest(source, filter)
                |> mapToSignal { source, filter -> Signal<NovagramTranslatedMessages?, NoError> in
                    let searchLocation = location.withUpdatedSouce(source).novagramDates(filter)
                    let limit = Int32(novagramTranslatedLimit)
                    let search = engine.messages.searchMessages(
                        location: searchLocation,
                        query: text,
                        state: nil,
                        limit: limit
                    )
                    return search
                        |> map { result, _ -> NovagramTranslatedMessages? in
                            let readStates = result.readStates
                            let messages = result.messages
                            let kept = novagramSearchKeptMessages(messages, readStates: readStates, filter: filter)
                            return NovagramTranslatedMessages(
                                text: text,
                                messages: Array(kept.prefix(novagramTranslatedLimit)),
                                readStates: result.readStates,
                                threadInfo: result.threadInfo
                            )
                        }
                }
        }
    return .single(nil) |> then(translated)
}

func novagramTranslatedRows(
    _ value: NovagramTranslatedMessages?,
    shown: [ChatListSearchEntryStableId]
) -> NovagramTranslatedMessages? {
    guard let value else {
        return nil
    }
    var shownIds = Set<MessageId>()
    for case let .messageId(messageId) in shown {
        shownIds.insert(messageId)
    }
    let messages = value.messages.filter { !shownIds.contains($0.id) }
    if messages.isEmpty {
        return nil
    }
    return NovagramTranslatedMessages(
        text: value.text,
        messages: messages,
        readStates: value.readStates,
        threadInfo: value.threadInfo
    )
}
