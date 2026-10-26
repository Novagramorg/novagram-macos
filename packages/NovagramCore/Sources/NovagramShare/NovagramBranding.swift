import AppKit

// The app is Novagram. Texts we do not own (server language packs, the bundled English
// strings, the menu from MainMenu.xib) still say "Telegram", so they are rebranded at runtime
// instead of editing every upstream string file. Lowercase URLs like telegram.org are kept.
public enum NovagramBranding {
    // Telegram's own updater downloads official Telegram builds from a Telegram channel and would
    // install them over Novagram. Novagram updates come from the App Store only.
    public static let allowsTelegramUpdater = false

    // Tag of the "Check for Updates" item in MainMenu.xib (upstream removes it only in APP_STORE builds).
    public static let checkForUpdatesMenuTag = 1000

    public static func rebrand(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "Telegram", with: "Novagram")
            .replacingOccurrences(of: "TELEGRAM", with: "NOVAGRAM")
            .replacingOccurrences(of: "Fenixuz", with: "Novagram")
            .replacingOccurrences(of: "FENIXUZ", with: "NOVAGRAM")
    }

    public static func rebrandMenu(_ menu: NSMenu?) {
        guard let menu = menu else {
            return
        }
        for item in menu.items {
            item.title = rebrand(item.title)
            if let submenu = item.submenu {
                submenu.title = rebrand(submenu.title)
                rebrandMenu(submenu)
            }
        }
    }
}
