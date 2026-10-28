import Foundation

// iOS "Folder display style" (`fenix_folder_display_style`): "icon" shows a folder's emoji instead of its
// name on the folder tabs. "text" and "auto" keep the name (iOS has no separate rule for "auto").
public enum NovagramFolderStyle {
    public static let defaultsKey = "fenix_folder_display_style"
    public static let options = ["auto", "icon", "text"]

    public static var current: String {
        return UserDefaults(suiteName: NovagramSettingsKey.suite)?.string(forKey: defaultsKey) ?? "auto"
    }

    public static func set(_ style: String) {
        UserDefaults(suiteName: NovagramSettingsKey.suite)?.set(style, forKey: defaultsKey)
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    public static func showsEmoji(_ emoticon: String?) -> Bool {
        guard current == "icon", let emoticon, !emoticon.isEmpty else {
            return false
        }
        return true
    }

    public static func tabTitle(_ title: String, emoticon: String?) -> String {
        if showsEmoji(emoticon), let emoticon {
            return emoticon
        }
        return title
    }
}
