import Foundation

struct RecordingTrimState {
    let duration: Double
    let range: Range<Double>

    init(duration: Double, range: Range<Double>?) {
        guard duration.isFinite, duration > 0 else {
            self.duration = 0
            self.range = 0 ..< 0
            return
        }
        self.duration = duration
        if let range, range.lowerBound.isFinite, range.upperBound.isFinite {
            let lower = min(duration, max(0, range.lowerBound))
            let upper = min(duration, max(0, range.upperBound))
            self.range = lower < upper ? lower ..< upper : 0 ..< duration
        } else {
            self.range = 0 ..< duration
        }
    }

    func position(_ value: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
