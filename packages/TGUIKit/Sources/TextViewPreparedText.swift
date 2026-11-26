import AppKit
import CoreText

final class TextViewPreparedText {
    let source: NSAttributedString
    let attributedString: NSAttributedString
    let typesetter: CTTypesetter
    let needsRunDecorations: Bool
    private var hasImmutableAttributes: Bool?

    init(source: NSAttributedString, attributedString: NSAttributedString, typesetter: CTTypesetter, needsRunDecorations: Bool) {
        self.source = source
        self.attributedString = attributedString
        self.typesetter = typesetter
        self.needsRunDecorations = needsRunDecorations
    }

    func matches(_ string: NSAttributedString) -> Bool {
        if hasImmutableAttributes == nil {
            var immutable = true
            source.enumerateAttributes(in: NSRange(location: 0, length: source.length), options: [.longestEffectiveRangeNotRequired]) { attributes, _, stop in
                for value in attributes.values {
                    if value is NSFont || value is NSNumber || value is NSURL {
                        continue
                    } else if let color = value as? NSColor, color.type == .componentBased {
                        continue
                    } else if value is NSString && !(value is NSMutableString) {
                        continue
                    } else if let paragraph = value as? NSParagraphStyle, !(paragraph is NSMutableParagraphStyle), paragraph.textBlocks.isEmpty, paragraph.textLists.isEmpty, paragraph.tabStops.allSatisfy({ $0.options.isEmpty }) {
                        continue
                    }
                    immutable = false
                    stop.pointee = true
                    break
                }
            }
            hasImmutableAttributes = immutable
        }
        return hasImmutableAttributes == true && source.isEqual(to: string)
    }
}
