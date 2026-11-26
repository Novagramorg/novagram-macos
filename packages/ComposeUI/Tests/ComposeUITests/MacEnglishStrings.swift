import Foundation
import TelegramCore
import Localization

func macEnglishStrings() -> [String: String] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return NSDictionary(contentsOf: root.appendingPathComponent("Telegram-Mac/en.lproj/Localizable.strings")) as? [String: String] ?? [:]
}

func applyMacEnglishStrings(_ strings: [String: String] = macEnglishStrings()) {
    let entries = strings.map { LocalizationEntry.string(key: $0.key, value: $0.value) }
    let component = LocalizationComponent(languageCode: "en", localizedName: "English", localization: TelegramCore.Localization(version: 0, entries: entries), customPluralizationCode: nil)
    applyUILocalization(LocalizationSettings(primaryComponent: component, secondaryComponent: nil))
}
