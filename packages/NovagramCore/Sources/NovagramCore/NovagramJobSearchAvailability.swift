import Foundation
import SwiftSignalKit

public enum NovagramJobSearchAvailability {
    public static let key = NovagramDeveloperFlags.jobSearchKey

    public static var isEnabled: Bool {
        return NovagramDeveloperFlags.isJobSearchEnabled
    }

    public static func signal() -> Signal<Bool, NoError> {
        return NovagramDeveloperFlags.jobSearchSignal
    }
}
