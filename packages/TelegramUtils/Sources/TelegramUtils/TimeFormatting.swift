import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import Localization
import SwiftSignalKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif

public func autoremoveLocalized(_ ttl: Int, roundToCeil: Bool = false) -> String {
    var localized: String = ""
     if ttl <= 59 {
        localized = strings().timerSecondsOther(ttl)
    } else if ttl <= 3599 {
        localized = strings().timerMinutesOther(ttl / 60)
    } else if ttl <= 86399 {
        localized = strings().timerHoursOther(ttl / 60 / 60)
    } else if ttl <= 604799 {
        if roundToCeil {
            localized = strings().timerDaysOther(Int(ceil(Float(ttl) / 60 / 60 / 24)))
        } else {
            localized = strings().timerDaysOther(ttl / 60 / 60 / 24)
        }
    } else {
        if roundToCeil {
            localized = strings().timerWeeksOther(Int(ceil(Float(ttl) / 60 / 60 / 24 / 7)))
        } else {
            let weeks = ttl / 60 / 60 / 24 / 7
            if weeks >= 4 {
                localized = strings().timerMonthsOther(weeks / 4)
            } else {
                localized = strings().timerWeeksOther(weeks)
            }
        }
    }
    return localized
}

public func shortTimeIntervalString(value: Int32) -> String {
    if value < 60 {
        return strings().messageTimerShortSeconds("\(max(1, value))")
    } else if value < 60 * 60 {
        return strings().messageTimerShortMinutes("\(max(1, value / 60))")
    } else if value < 60 * 60 * 24 {
        return strings().messageTimerShortHours("\(max(1, value / (60 * 60)))")
    } else if value <= 60 * 60 * 24 * 7 {
        return strings().messageTimerShortDays("\(max(1, value / (60 * 60 * 24)))")
    } else {
        let weeks = max(1, value / (60 * 60 * 24 * 7))
        if weeks < 4 {
            return strings().messageTimerShortWeeks("\(weeks)")
        } else {
            return strings().messageTimerShortMonths("\(weeks / 4)")
        }
    }
}

public func slowModeTooltipText(_ timeout: Int32) -> String {
    let minutes = timeout / 60
    let seconds = timeout % 60
    return strings().channelSlowModeToolTip(minutes < 10 ? "0\(minutes)" : "\(minutes)", seconds < 10 ? "0\(seconds)" : "\(seconds)")
}

public func timeIntervalString( _ value: Int, months: Bool = false) -> String {
    if value < 60 {
        return strings().timerSecondsOther(value)
    } else if value < 60 * 60 {
        return strings().timerMinutesOther(max(1, value / 60))
    } else if value < 60 * 60 * 24 {
        return strings().timerHoursOther(max(1, value / (60 * 60)))
    } else if value < 60 * 60 * 24 * 7 {
        return strings().timerDaysOther(max(1, value / (60 * 60 * 24)))
    } else if value < 60 * 60 * 24 * 30 {
        return strings().timerWeeksOther(max(1, value / (60 * 60 * 24 * 7)))
    } else if value < 60 * 60 * 24 * 360 || months {
        return strings().timerMonthsOther(max(1, value / (60 * 60 * 24 * 30)))
    } else {
        return strings().timerYearsOther(max(1, value / (60 * 60 * 24 * 365)))
    }
}

public func timerText(_ durationValue: Int, addminus: Bool = true) -> String {

    let duration = abs(durationValue)
    let days = Int(duration) / (3600 * 24)
    let hours = (Int(duration) - (days * 3600 * 24)) / 3600
    let minutes = Int(duration) / 60 % 60
    let seconds = Int(duration) % 60



    var formatted: String
    if days >= 1 {
        formatted = timeIntervalString(duration)
    } else if days != 0 {
        formatted = String(format:"%d:%02i:%02i:%02i", days, hours, minutes, seconds)
    } else if hours != 0 {
        formatted = String(format:"%02i:%02i:%02i", hours, minutes, seconds)
    } else {
        formatted = String(format:"%02i:%02i", minutes, seconds)
    }
    if addminus {
        return durationValue < 0 ? "-" + formatted : formatted
    } else {
        return formatted
    }
}
