import Foundation
import Localization

public extension String {
    static func stringForShortCallDurationSeconds(for seconds: Int32) -> String {
        if seconds < 60 {
            return strings().callShortSecondsOther(Int(seconds))
        }
        else {
            let number = Int(seconds) / 60
            return strings().callShortMinutesOther(number)
        }
    }
}
