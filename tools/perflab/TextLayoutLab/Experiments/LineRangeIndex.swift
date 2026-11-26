import Foundation

struct TextViewLineRangeIndex {
    private let ranges: [NSRange]
    private let isOrdered: Bool

    init(_ ranges: [NSRange]) {
        self.ranges = ranges
        var previousEnd = 0
        var ordered = true
        for range in ranges {
            let (end, overflow) = range.location.addingReportingOverflow(range.length)
            if overflow || range.location < previousEnd || range.length < 0 {
                ordered = false
                break
            }
            previousEnd = end
        }
        self.isOrdered = ordered
    }

    func candidates(intersecting range: NSRange) -> Range<Int> {
        guard range.length > 0 else {
            return 0 ..< 0
        }
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        guard isOrdered && !overflow else {
            return ranges.indices
        }
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if ranges[middle].location + ranges[middle].length <= range.location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let start = lower
        upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if ranges[middle].location < end {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return start ..< lower
    }
}
