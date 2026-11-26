import Foundation

func referenceForEachBoldItalicRange(bold: [NSRange], italic: [NSRange], apply: (NSRange) -> Void) {
    for boldRange in bold {
        for italicRange in italic {
            if let intersection = boldRange.intersection(italicRange) {
                apply(intersection)
            }
        }
    }
}
