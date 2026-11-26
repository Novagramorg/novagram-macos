import Foundation
import RangeSet

func audioPlayerBufferingRanges(_ ranges: RangeSet<Int64>, size: Int64) -> [Range<CGFloat>] {
    guard size > 0 else { return [] }
    let result = ranges.ranges.compactMap { range -> Range<CGFloat>? in
        let lower = max(0, min(size, range.lowerBound))
        let upper = max(0, min(size, range.upperBound))
        guard lower < upper else { return nil }
        return (CGFloat(lower) / CGFloat(size)) ..< (CGFloat(upper) / CGFloat(size))
    }
    return result == [0 ..< 1] ? [] : result
}
