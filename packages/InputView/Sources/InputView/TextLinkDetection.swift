import Cocoa
import TGUIKit
import ObjcUtils

public struct DetectedTextLink {
    public let text: String
    public let range: NSRange
}

public func detectedTextLinks(in text: String, type: ParsingType, dotInMention: Bool = false) -> [DetectedTextLink] {
        let things = ObjcUtils.textCheckingResults(forText: text, highlightMentions: type.contains(.Mentions), highlightTags: type.contains(.Hashtags), highlightCommands: type.contains(.Commands), dotInMention: dotInMention)?.compactMap {
            return ($0 as? NSValue)?.rangeValue
        } ?? []


        var copy: [NSRange] = []
        for thing in things {
            let contains = copy.contains(where: {
                $0.intersection(thing) != nil
            })
            if !contains {
                copy.append(thing)
            }
        }

    return copy.compactMap { range in
        guard range.location != NSNotFound else {
            return nil
        }
        return DetectedTextLink(text: (text as NSString).substring(with: range), range: range)
    }
}
