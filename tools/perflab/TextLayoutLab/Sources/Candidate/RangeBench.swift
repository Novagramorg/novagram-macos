import Foundation

public func binaryIntersectionCount(_ ranges: [NSRange], _ queries: [NSRange]) -> Int {
    let index = TextViewLineRangeIndex(ranges)
    var count = 0
    for query in queries {
        for row in index.candidates(intersecting: query) {
            if NSIntersectionRange(ranges[row], query).length > 0 { count += 1 }
        }
    }
    return count
}
