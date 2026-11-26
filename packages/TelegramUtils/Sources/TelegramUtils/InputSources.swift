import SwiftSignalKit
import TelegramContext
import Foundation
import TelegramCore
import ObjcUtils
import Postbox
import InAppSettings

public final class InputSources: NSObject {
    
    private let _inputSource: Promise<[String]> = Promise(["en"])
    
    public var value: Signal<[String], NoError> {
        _inputSource.set(Signal { subscriber in
            subscriber.putNext([currentKeyboardLanguage()])
            subscriber.putCompletion()
            return EmptyDisposable
        } |> runOn(.mainQueue()))
        return _inputSource.get() |> distinctUntilChanged(isEqual: { $0 == $1 })
    }
    
    public func searchEmoji(postbox: Postbox, engine: TelegramEngine, sharedContext: any SharedAccountContextProtocol, query: String, completeMatch: Bool, checkPrediction: Bool) -> Signal<[String], NoError> {
        return combineLatest(value, baseAppSettings(accountManager: sharedContext.accountManager)) |> mapToSignal { sources, settings in
            if settings.predictEmoji || !checkPrediction {
                let query = normalizedEmojiKeywordQuery(query)
                let emojis = query.emojis
                if !emojis.isEmpty, emojis.joined() == query.filter({ !$0.isWhitespace }) {
                    return .single(emojis.uniqueElements)
                }
                return searchEmojiKeywordMatches(query: query, languageCodes: sources, completeMatch: completeMatch, search: { language, query, completeMatch in
                    engine.stickers.searchEmojiKeywords(inputLanguageCode: language, query: query, completeMatch: completeMatch) |> map { entries in
                        entries.map { EmojiKeywordSearchEntry(keyword: $0.keyword, emoticons: $0.emoticons) }
                    }
                }) |> map { $0.isEmpty ? emojis : $0 }
            } else {
                return .single([])
            }
        }
    }
    
    
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(inputSourceChanged), name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func inputSourceChanged() {
        _inputSource.set(.single(currentAppInputSource().uniqueElements))
    }
}
