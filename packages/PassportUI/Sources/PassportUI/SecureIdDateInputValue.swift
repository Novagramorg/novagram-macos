import Foundation
import TelegramCore
import InputDataUI

public extension SecureIdDate {
    var inputDataValue: InputDataValue {
        return .date(day, month, year)
    }
}
