import Foundation
import CalendarUtils
import TelegramTheme

public struct DateSelectorUtil {
    
    public static var timeIntervals:[TimeInterval?]  {
        var intervals:[TimeInterval?] = []
        for i in 0 ... 23 {
            let current = Double(i) * 60.0 * 60
            intervals.append(current)
    //        #if DEBUG
            for i in 1 ... 59 {
                intervals.append(current + Double(i) * 60.0)
            }
            if i < 23 {
                intervals.append(nil)
            }

        }
        return intervals
    }

    public static let dayFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: appAppearance.language.languageCode)
        //dateFormatter.timeZone = TimeZone(abbreviation: "UTC")!
        dateFormatter.dateFormat = "MMM d, yyyy"
        return dateFormatter
    }()
    
    public static let chatDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .none
        dateFormatter.timeZone = NSTimeZone.local
        return dateFormatter
    }()
    
    public static let chatFullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.timeZone = NSTimeZone.local
        return formatter
    }()
    
    public static let mediaMediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = NSTimeZone.local
        return formatter
    }()
    
    public static let mediaDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = NSTimeZone.local
        formatter.dateFormat = "MMMM yyyy";
        return formatter
    }()
    
    public static let mediaFileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = NSTimeZone.local
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
    
    public static let chatImportedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = NSTimeZone.local
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    public static let dayFormatterRelative: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: appAppearance.language.languageCode)
       // dateFormatter.timeZone = TimeZone(abbreviation: "UTC")!

        dateFormatter.dateStyle = .short
        dateFormatter.doesRelativeDateFormatting = true
        return dateFormatter
    }()

    public static func formatDay(_ date: Date) -> String {
        if CalendarUtils.isSameDate(date, date: Date(), checkDay: true) {
            return dayFormatterRelative.string(from: date)
        } else {
            return dayFormatter.string(from: date)
        }
    }

    public static let timerFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium
        return timeFormatter
    }()
    
    public static func formatTime(_ date: Date) -> String {
        return timerFormatter.string(from: date)
    }
    
    
    public static let timerShortFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return timeFormatter
    }()
    
    public static func shortFormatTime(_ date: Date) -> String {
        return timerShortFormatter.string(from: date)
    }
}
