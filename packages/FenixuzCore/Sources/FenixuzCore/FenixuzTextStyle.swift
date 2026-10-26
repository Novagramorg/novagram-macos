import Foundation

// One format applied to every outgoing text message (Settings → Novagram → Messages → Text style).
public enum FenixuzTextStyle: String, CaseIterable {
    case none           = "none"
    case bold           = "bold"
    case italic         = "italic"
    case monospace      = "monospace"
    case strikethrough  = "strikethrough"
    case underline      = "underline"
    case spoiler        = "spoiler"

    public static var current: FenixuzTextStyle {
        let raw = UserDefaults(suiteName: "pro_messager")?.string(forKey: "text_style") ?? "none"
        return FenixuzTextStyle(rawValue: raw) ?? .none
    }
}
