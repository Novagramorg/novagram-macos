import SwiftSignalKit
import TelegramCore
import Postbox

struct EmojiPanelSearchData {
    let values: [String]?
    let isLoading: Bool
    var files: [TelegramMediaFile] = []
    var packs = FoundStickerSets()
    var context: EmojiSearchContext?
}

func panelCustomEmojiSearch(engine: TelegramEngine, query: String?, values: [String], languageCode: String) -> Signal<EmojiPanelSearchData, NoError> {
    let context = engine.stickers.emojiSearchContext(query: query, emoticon: values, inputLanguageCode: languageCode)
    let packs: Signal<(FoundStickerSets, Bool), NoError>
    if let query = query, !query.isEmpty {
        let remote = Signal<FoundStickerSets, NoError> { subscriber in
            var receivedResult = false
            return engine.stickers.searchEmojiSetsRemotely(query: query).start(next: { result in
                receivedResult = true
                subscriber.putNext(result)
            }, completed: {
                if !receivedResult {
                    subscriber.putNext(FoundStickerSets())
                }
                subscriber.putCompletion()
            })
        }
        packs = engine.stickers.searchEmojiSets(query: query) |> mapToSignal { local in
            return .single((local, true)) |> then(remote |> map { (local.merge(with: $0), false) })
        }
    } else {
        packs = .single((FoundStickerSets(), false))
    }
    return combineLatest(context.state, packs) |> map { [context] emoji, packs in
        return EmojiPanelSearchData(values: values, isLoading: emoji.isLoadingMore || packs.1, files: emoji.items, packs: packs.0, context: context)
    }
}

struct EmojiPanelSearchPack {
    let info: StickerPackCollectionInfo
    let items: [StickerPackItem]
    let installed: Bool
}

func panelEmojiMatchingPacks(_ packs: FoundStickerSets, installedIds: Set<ItemCollectionId>) -> [EmojiPanelSearchPack] {
    let matchingItems = Dictionary(grouping: packs.entries, by: { $0.index.collectionId })
    var matchingIds = Set<ItemCollectionId>()
    return packs.infos.compactMap { collectionId, info, _, installed in
        guard let info = info as? StickerPackCollectionInfo, matchingIds.insert(collectionId).inserted else { return nil }
        let items = panelSearchAppendingUnique([], (matchingItems[collectionId] ?? []).compactMap { $0.item as? StickerPackItem }, id: { $0.file.fileId })
        guard !items.isEmpty else { return nil }
        return EmojiPanelSearchPack(info: info, items: items, installed: installed || installedIds.contains(collectionId))
    }
}
