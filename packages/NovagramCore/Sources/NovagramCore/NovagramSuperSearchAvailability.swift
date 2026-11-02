import Foundation
import SwiftSignalKit

public enum NovagramSuperSearchAvailability {
    public static let key = NovagramDeveloperFlags.superSearchKey

    public static var isEnabled: Bool {
        return NovagramDeveloperFlags.isSuperSearchEnabled
    }

    public static func signal() -> Signal<Bool, NoError> {
        return NovagramDeveloperFlags.superSearchSignal
    }
}
