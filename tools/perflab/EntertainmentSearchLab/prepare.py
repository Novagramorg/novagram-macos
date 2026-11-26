from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
out = lab / "Sources/SearchLab"
files = {
    "EmojiKeywordSearch": "packages/TelegramUtils/Sources/TelegramUtils/EmojiKeywordSearch.swift",
    "PanelSearchPresentation": "packages/EntertainmentUI/Sources/EntertainmentUI/PanelSearchPresentation.swift",
    "PanelSearchState": "packages/EntertainmentUI/Sources/EntertainmentUI/PanelSearchState.swift",
}
provenance = {}
for name, relative in files.items():
    source = (root / relative).read_text()
    (out / f"Generated{name}.swift").write_text(source)
    provenance[relative] = hashlib.sha256(source.encode()).hexdigest()

def read(relative):
    source = (root / relative).read_text()
    provenance[relative] = hashlib.sha256(source.encode()).hexdigest()
    return source

gif = read("packages/EntertainmentUI/Sources/EntertainmentUI/GifKeyboardController.swift")
start = gif.index("        var searchRequests = PanelSearchRequestTracker")
end = gif.index("        let searchInteractions =", start)
body = gif[start:end]
(out / "GeneratedGifSearch.swift").write_text('''import Foundation
import SwiftSignalKit

extension GifHarness {
    func install() {
        let context = self.context
        let stateValue = self.stateValue
        let disposableDict = self.disposableDict
        let updateState: ((State) -> State) -> Void = { f in _ = stateValue.modify(f) }
        let updateSearchCommand: () -> Void = { [weak self] in self?.completedCount += 1 }
''' + body + '''
        self.search = makeSearch
        self.update = updateSearchState
    }
}
''')

stickers = read("packages/EntertainmentUI/Sources/EntertainmentUI/StickersViewController.swift")
start = stickers.index("                    emojiRelated = combineLatest(EntertainmentUIHooks")
end = stickers.index("\n                }", start)
body = stickers[start:end]
(out / "GeneratedStickerSearch.swift").write_text('''import Foundation
import SwiftSignalKit
import Strings

func stickerSearch(context: StickerContext, searchText: String, input: Signal<String, NoError>) -> Signal<([FoundStickerItem], Bool), NoError> {
    let emojiRelated: Signal<([FoundStickerItem], Bool), NoError>
''' + body + '''
    return emojiRelated
}
''')

emoji = read("packages/EntertainmentUI/Sources/EntertainmentUI/EmojiesController.swift")
start = emoji.index("        let searchQueries = self.searchValue.get()")
end = emoji.index("        let combined = statePromise.get()", start)
(out / "GeneratedEmojiSearch.swift").write_text('''import Foundation
import SwiftSignalKit

extension EmojiHarness {
    func fullSearchResults() -> Signal<EmojiPanelSearchData, NoError> {
        let mode = self.mode
        let context = self.context
        let initialState = CategoryState()
        let statePromise = self.statePromise
        let prepareQueue = Queue.mainQueue()
''' + emoji[start:end] + '''
        return search
    }
    func searchResults() -> Signal<PanelEmojiSearchResult, NoError> {
        return fullSearchResults() |> map { PanelEmojiSearchResult(values: $0.values, isLoading: $0.isLoading) }
    }
}
''')
start = stickers.index("        let searchQueries = self.searchValue.get()")
end = stickers.index("        let signal = searchInputs", start)
(out / "GeneratedStickerInputs.swift").write_text('''import Foundation
import SwiftSignalKit

extension EmojiHarness {
    func stickerInputs() -> Signal<(String, Position, EmojiCategory?), NoError> {
        let initialState = CategoryState()
        let statePromise = self.statePromise
        let prepareQueue = Queue.mainQueue()
''' + stickers[start:end] + '''
        return searchInputs
    }
}
''')

start = stickers.index("                let searchLocal: Signal<FoundStickerSets?")
end = stickers.index("\n                \n            }", start)
(out / "GeneratedStickerResults.swift").write_text('''import Foundation
import SwiftSignalKit
import Strings

func stickerResults(context: StickerContext, query: String, category: EmojiCategory? = nil) -> Signal<StickerPacksUpdateData, NoError> {
    let values: (String, Position, EmojiCategory?) = (query, .initial, category)
    let searchText = query
    let mode = 0
    let prepareQueue = Queue.mainQueue()
    let statePromise = ValuePromise(CategoryState(selectedEmojiCategory: category))
    let premiumStickers: Signal<[File], NoError> = .single([])
''' + stickers[start:end] + '\n}\n')

inputs = read("packages/TelegramUtils/Sources/TelegramUtils/InputSources.swift")
start = inputs.index("    public func searchEmoji(")
end = inputs.index("    public override init()", start)
extensions = read("packages/TGUIKit/Sources/Extensions.swift")
a = extensions.index("public extension Sequence where Iterator.Element: Hashable {")
b = extensions.index("public extension Sequence where Iterator.Element: Equatable {", a)
(out / "GeneratedInputSources.swift").write_text('''import Foundation
import SwiftSignalKit
import Strings

final class InputSources {
    let value: Signal<[String], NoError>
    init(languages: [String]) { value = .single(languages) }
''' + inputs[start:end] + '\n}\n' + extensions[a:b])
(lab / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
print(f"Prepared and recorded {len(provenance)} production sources")

initializers = "import SwiftSignalKit\n"
for name, source in (("Emoji", emoji), ("Sticker", stickers)):
    start = source.index("        let statePromise = ValuePromise<State>")
    end = source.index("\n", start)
    initializers += f"\nfunc make{name}StatePromise() -> ValuePromise<CategoryState> {{\n    typealias State = CategoryState\n    let initialState = State()\n" + source[start:end] + "\n    return statePromise\n}\n"
(out / "GeneratedStateInitialization.swift").write_text(initializers)

start = stickers.index("private func stickerSearchHasResults(")
end = stickers.index("public class NStickersView", start)
(out / "GeneratedStickerSearchContent.swift").write_text(stickers[start:end].replace("private func", "func", 1))

import re
start = emoji.index("    static func ==(lhs: State, rhs: State)")
end = emoji.index("    struct ExternalTopic", start)
comparison = emoji[start:end]
fields = set(re.findall(r"lhs\.(\w+)", comparison))
properties = "    var search: [String]? = []\n    var searchLoading = false\n"
for field in sorted(fields - {"search", "searchLoading"}):
    properties += f"    var {field}: [Int] = []\n"
(out / "GeneratedEmojiStateEquality.swift").write_text("struct EmojiStateEqualityFixture: Equatable {\n    typealias State = EmojiStateEqualityFixture\n" + properties + comparison + "}\n")

custom = read("packages/EntertainmentUI/Sources/EntertainmentUI/EmojiPanelSearchData.swift")
(out / "GeneratedCustomEmojiSearch.swift").write_text(custom.replace("import TelegramCore\n", "").replace("import Postbox\n", ""))
assert "for (i, section) in displayedSections.enumerated()" in emoji
assert "panelEmojiDisplayedSections(isSearching: state.search != nil, isMessageEffects: arguments.mode == .messageEffects, browsing: state.sections, matching: state.searchSections)" in emoji
assert "if !search.isEmpty || !state.searchFiles.isEmpty" in emoji
assert "if state.search == nil, !state.uniqueStarGiftsItems.isEmpty" in emoji
(lab / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")

start = emoji.index("        static func ==(lhs: Section, rhs: Section)")
end = emoji.index("    var sections:[Section]", start)
comparison = emoji[start:end].rsplit("    }", 1)[0]
(out / "GeneratedEmojiSectionEquality.swift").write_text("""struct EmojiSectionEqualityFixture: Equatable {
    typealias Section = EmojiSectionEqualityFixture
    var info = 0
    var installed = false
    var items: [Int] = []
    var dict: [Int: Int] = [:]
    var groupEmojiPack = false
    var isBig = false
""" + comparison + "}\n")
