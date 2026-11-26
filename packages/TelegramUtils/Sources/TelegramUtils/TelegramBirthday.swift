import Foundation
import TelegramCore
import Localization
import CalendarUtils

public extension TelegramBirthday {
    var dateForPicker: Date? {
        let calendar = Calendar(identifier: .gregorian)
        let year = self.year.map(Int.init) ?? CalendarUtils.yearForNoYear
        guard let date = calendar.date(from: DateComponents(year: year, month: Int(self.month), day: Int(self.day))) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year, components.month == Int(self.month), components.day == Int(self.day) else { return nil }
        return date
    }

    var isToday: Bool {
        let date = Date()
        let calendar = Calendar(identifier: .gregorian)

        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        
        return self.day == day && self.month == month
    }
    
    func isTomorrow() -> Bool {
        let currentDate = Date()
        let calendar = Calendar(identifier: .gregorian)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) else { return false }

        let dayTomorrow = calendar.component(.day, from: tomorrow)
        let monthTomorrow = calendar.component(.month, from: tomorrow)

        return day == dayTomorrow && month == monthTomorrow
    }

    func isYesterday() -> Bool {
        let currentDate = Date()
        let calendar = Calendar(identifier: .gregorian)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: currentDate) else { return false }

        let dayYesterday = calendar.component(.day, from: yesterday)
        let monthYesterday = calendar.component(.month, from: yesterday)

        return day == dayYesterday && month == monthYesterday
    }
    
    
    func yearsSince() -> Int? {
        guard self.year != nil, let fromDate = self.dateForPicker else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.dateComponents([.year], from: fromDate, to: Date()).year
    }

    var isEligble: Bool {
        return self.isToday || self.isTomorrow() || self.isYesterday()
    }
    var formatted: String {
        return formatBirthdayToString(day: Int(self.day), month: Int(self.month), year: self.year.flatMap(Int.init)) ?? ""
    }
    var formattedYears: String {
        if let year = yearsSince(), year > 0 {
            let string = formatted + " (\(strings().birthdayYearsOldOther(year)))"
            if isToday {
                return "🎂 " + string
            } else {
                return string
            }
        } else {
            return formatted
        }
    }
}