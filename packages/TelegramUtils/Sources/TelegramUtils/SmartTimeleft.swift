import Foundation
import FoundationUtils

public func smartTimeleftText( _ left: Int) -> String {
    if left <= Int(Int32.secondsInDay) {
        let minutes = left / 60 % 60
        let seconds = left % 60
        let hours = left / 60 / 60
        let string = String(format: "%@:%@:%@", hours < 10 ? "0\(hours)" : "\(hours)", minutes < 10 ? "0\(minutes)" : "\(minutes)", seconds < 10 ? "0\(seconds)" : "\(seconds)")
        return string
    } else {
        return autoremoveLocalized(left, roundToCeil: true)
    }
}
