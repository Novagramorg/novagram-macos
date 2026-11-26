import Foundation
import Cocoa

public func digitsOnlyFilterEvent(_ event: NSEvent) -> Bool {
    if let chars = event.characters {
        return chars.trimmingCharacters(in: CharacterSet(charactersIn: "1234567890\u{7f}")).isEmpty
    } else {
        return false
    }
}
