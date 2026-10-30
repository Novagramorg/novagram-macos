import Cocoa
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import NovagramCore
import NovagramSearchKit

struct NovagramTranslatedMessages {
    let target: String
    let text: String
    let messages: [Message]
    let readStates: [PeerId: CombinedPeerReadState]
    let threadInfo: [MessageId: MessageHistoryThreadData]

    var title: String {
        return NovagramL10n.current.search_translatedTitle(text) + " · " + NovagramQueryTranslator.targetName(target)
    }
}

final class NovagramTranslateChipsState {
    private let value = Atomic<Set<String>>(value: Set())
    private let promise = ValuePromise<Set<String>>(Set(), ignoreRepeated: true)

    var disabled: Signal<Set<String>, NoError> {
        return promise.get()
    }

    func toggle(_ target: String) {
        let next = value.modify { current in
            var current = current
            if current.contains(target) {
                current.remove(target)
            } else {
                current.insert(target)
            }
            return current
        }
        promise.set(next)
    }
}

struct NovagramTranslateChips: Equatable {
    let targets: [String]
    let disabled: Set<String>
    let state: NovagramTranslateChipsState

    static func == (lhs: NovagramTranslateChips, rhs: NovagramTranslateChips) -> Bool {
        return lhs.targets == rhs.targets && lhs.disabled == rhs.disabled && lhs.state === rhs.state
    }
}

struct NovagramTranslatedResult {
    let targets: [String]
    let sections: [NovagramTranslatedMessages]
    let disabled: Set<String>
    let chips: NovagramTranslateChipsState
}

struct NovagramTranslatedBlock {
    let title: String
    let index: Int
    let chips: NovagramSavedSearchRow?
    let text: String
    let messages: [Message]
    let readStates: [PeerId: CombinedPeerReadState]
    let threadInfo: [MessageId: MessageHistoryThreadData]

    var firstMessageIndex: Int {
        return index + (chips == nil ? 1 : 2)
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
        return !NovagramQueryTranslation.skippedPrefixes.contains(where: { query.hasPrefix($0) })
    }
}

private let novagramTranslatedLimit = NovagramSearchPaging.translatedResultLimit
private let novagramTranslatedFirstIndex = 19000
private let novagramTranslatedIndexStride = 25

func novagramTranslatedSearch(
    _ context: any AccountContextProtocol,
    scope: NovagramTranslatedScope,
    location: SearchMessagesLocation,
    source: Signal<SearchControllerMessaagesSourceValue, NoError>,
    filter: Signal<NovagramSearchFilterState, NoError>
) -> Signal<NovagramTranslatedResult?, NoError> {
    return NovagramSearchFeatures.signal()
        |> mapToSignal { enabled -> Signal<NovagramTranslatedResult?, NoError> in
            guard enabled else {
                return .single(nil)
            }
            return novagramTranslatedSections(context, scope: scope, location: location, source: source, filter: filter)
        }
}

private func novagramTranslatedSections(
    _ context: any AccountContextProtocol,
    scope: NovagramTranslatedScope,
    location: SearchMessagesLocation,
    source: Signal<SearchControllerMessaagesSourceValue, NoError>,
    filter: Signal<NovagramSearchFilterState, NoError>
) -> Signal<NovagramTranslatedResult?, NoError> {
    guard scope.applies, NovagramSearchFeatures.isEnabled, NovagramQueryTranslator.isEnabled else {
        return .single(nil)
    }
    let engine = context.engine
    let allTargets = NovagramQueryTranslator.targets
    var translations: [String: Signal<String?, NoError>] = [:]
    for code in NovagramQueryTranslator.serverCodes(for: allTargets) {
        translations[code] = NovagramQueryTranslator.translatedQuery(engine: engine, query: scope.query, language: code)
    }
    let targets = allTargets.filter { target in
        NovagramQueryTranslator.serverCode(for: target).map { translations[$0] != nil } ?? false
    }
    guard !targets.isEmpty else {
        return .single(nil)
    }
    let sections = targets.compactMap { target -> Signal<NovagramTranslatedMessages?, NoError>? in
        guard let code = NovagramQueryTranslator.serverCode(for: target), let translation = translations[code] else {
            return nil
        }
        let text = translation |> map { novagramTargetText($0, target: target, query: scope.query) }
        return novagramTranslatedMessages(engine, target: target, text: text, location: location, source: source, filter: filter)
    }
    let chips = NovagramTranslateChipsState()
    return combineLatest(combineLatest(sections), chips.disabled)
        |> map { sections, disabled -> NovagramTranslatedResult? in
            return NovagramTranslatedResult(targets: targets, sections: sections.compactMap { $0 }, disabled: disabled, chips: chips)
        }
}

private func novagramTargetText(_ translation: String?, target: String, query: String) -> String? {
    guard let translation else {
        return nil
    }
    guard target == NovagramSearchLanguage.uzCyrillic.rawValue else {
        return translation
    }
    let converted = NovagramSearchTransliteration.uzbekLatinToCyrillic(translation)
    return NovagramQueryTranslation.sectionText(translation: converted, query: query)
}

private func novagramTranslatedMessages(
    _ engine: TelegramEngine,
    target: String,
    text: Signal<String?, NoError>,
    location: SearchMessagesLocation,
    source: Signal<SearchControllerMessaagesSourceValue, NoError>,
    filter: Signal<NovagramSearchFilterState, NoError>
) -> Signal<NovagramTranslatedMessages?, NoError> {
    let translated: Signal<NovagramTranslatedMessages?, NoError> = text
        |> mapToSignal { text -> Signal<NovagramTranslatedMessages?, NoError> in
            guard let text else {
                return .single(nil)
            }
            return combineLatest(source, filter)
                |> mapToSignal { source, filter -> Signal<NovagramTranslatedMessages?, NoError> in
                    let searchLocation = location.withUpdatedSouce(source).novagramDates(filter)
                    let search = engine.messages.searchMessages(
                        location: searchLocation,
                        query: text,
                        state: nil,
                        limit: Int32(novagramTranslatedLimit)
                    )
                    return search
                        |> map { result, _ -> NovagramTranslatedMessages? in
                            let kept = novagramSearchKeptMessages(result.messages, readStates: result.readStates, filter: filter)
                            return NovagramTranslatedMessages(
                                target: target,
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

func novagramTranslatedBlocks(
    _ value: NovagramTranslatedResult?,
    shown: [ChatListSearchEntryStableId]
) -> [NovagramTranslatedBlock] {
    guard let value else {
        return []
    }
    var seen = Set<MessageId>()
    for case let .messageId(messageId) in shown {
        seen.insert(messageId)
    }
    var visible: [(section: NovagramTranslatedMessages, messages: [Message])] = []
    for section in value.sections where !value.disabled.contains(section.target) {
        let messages = section.messages.filter { seen.insert($0.id).inserted }
        if !messages.isEmpty {
            visible.append((section, messages))
        }
    }
    guard !visible.isEmpty || !value.disabled.isEmpty else {
        return []
    }
    let chips = NovagramSavedSearchRow(search: nil, index: novagramTranslatedFirstIndex + 1, chips: NovagramTranslateChips(targets: value.targets, disabled: value.disabled, state: value.chips))
    guard !visible.isEmpty else {
        return [NovagramTranslatedBlock(title: NovagramL10n.current.settings_searchTranslateLangs_title, index: novagramTranslatedFirstIndex, chips: chips, text: "", messages: [], readStates: [:], threadInfo: [:])]
    }
    return visible.enumerated().map { offset, item in
        NovagramTranslatedBlock(
            title: item.section.title,
            index: novagramTranslatedFirstIndex + offset * novagramTranslatedIndexStride,
            chips: offset == 0 ? chips : nil,
            text: item.section.text,
            messages: item.messages,
            readStates: item.section.readStates,
            threadInfo: item.section.threadInfo
        )
    }
}
