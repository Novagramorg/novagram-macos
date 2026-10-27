import Foundation

// Premium-only features Novagram gives every user (parity with the iOS PremiumUnlock module).
public enum NovagramPremiumUnlock {
    public static let wholeChatTranslate = true
    public static let folderTags = true
    public static let storiesSaveAndHD = true
    // Client-side folder count cap (iOS UserLimitsConfiguration hook: max(1000, server limit)).
    // Off by default (Settings → Novagram → Unlimited folders): 0 leaves the Telegram limits in place.
    // The Telegram server still applies its own cap when a folder is saved.
    public static var folderLimit: Int {
        return NovagramSettingsKey.bool("unlimited_folders") ? 1000 : 0
    }
}
