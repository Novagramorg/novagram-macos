import Foundation
import TelegramCore
import InputDataUI

public extension InputDataValue {
    var secureIdDate: SecureIdDate? {
        switch self {
        case let .date(day, month, year):
            if let day = day, let month = month, let year = year {
                return SecureIdDate(day: day, month: month, year: year)
            }
            return nil
        default:
            return nil
        }
    }
}
