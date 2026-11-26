import Foundation

func chatForEachBoldItalicRange(bold: [NSRange], italic: [NSRange], apply: (NSRange) -> Void) {
    guard !bold.isEmpty, !italic.isEmpty else {
        return
    }
    if bold.count == 1 || italic.count == 1 || (bold.count <= 16 && italic.count <= 16) {
        for boldRange in bold {
            for italicRange in italic {
                if let intersection = boldRange.intersection(italicRange) {
                    apply(intersection)
                }
            }
        }
        return
    }

    func merged(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        result.reserveCapacity(sorted.count)
        for range in sorted where range.length > 0 {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
            } else {
                result.append(range)
            }
        }
        return result
    }

    let bold = merged(bold)
    let italic = merged(italic)
    var b = 0
    var i = 0
    while b < bold.count && i < italic.count {
        let start = max(bold[b].location, italic[i].location)
        let boldEnd = NSMaxRange(bold[b])
        let italicEnd = NSMaxRange(italic[i])
        let end = min(boldEnd, italicEnd)
        if start < end {
            apply(NSRange(location: start, length: end - start))
        }
        if boldEnd < italicEnd {
            b += 1
        } else if italicEnd < boldEnd {
            i += 1
        } else {
            b += 1
            i += 1
        }
    }
}
