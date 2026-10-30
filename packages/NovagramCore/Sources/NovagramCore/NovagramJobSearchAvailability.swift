import Foundation
import SwiftSignalKit

public enum NovagramJobSearchAvailability {
    public static let key = NovagramSearchFeatures.key

    public static var isEnabled: Bool {
        return NovagramSearchFeatures.isEnabled
    }

    public static func signal() -> Signal<Bool, NoError> {
        return NovagramSearchFeatures.signal()
    }
}
