import Foundation
import Localization

public extension String {
    var isSavedMessagesText: Bool {
        let query = self.lowercased()
        if Localization.strings().peerSavedMessages.lowercased().hasPrefix(query) {
            return true
        }
        if NSLocalizedString("Peer.SavedMessages", comment: "nil").hasPrefix(query.lowercased()) {
            return true
        }
        return false
    }
}
