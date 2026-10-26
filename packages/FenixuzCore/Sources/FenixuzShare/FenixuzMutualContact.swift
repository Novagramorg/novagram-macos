import Foundation
import Postbox
import TelegramCore

// 🤝 after the name of users who also saved you as a contact (Settings → Novagram → Interface).
public enum FenixuzMutualContact {
    private static let defaults = UserDefaults(suiteName: "pro_messager")

    public static var isEnabled: Bool {
        return defaults?.object(forKey: "show_mutual_contact_symbol") as? Bool ?? true
    }

    public static func title(_ title: String, for peer: Peer) -> String {
        guard isEnabled, let user = peer as? TelegramUser, user.flags.contains(.mutualContact) else {
            return title
        }
        return title + " 🤝"
    }
}
