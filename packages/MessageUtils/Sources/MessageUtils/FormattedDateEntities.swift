import Foundation
import TelegramCore
import TelegramUtils

public func resolveFormattedDateEntities(_ text: String, entities: [MessageTextEntity]) -> (text: String, entities: [MessageTextEntity]) {
    var replacements: [(range: Range<Int>, text: String)] = []
    for entity in entities.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        guard case let .FormattedDate(format?, date) = entity.type else {
            continue
        }
        if let last = replacements.last, entity.range.lowerBound < last.range.upperBound {
            continue
        }
        replacements.append((entity.range, formatDateTimeEntity(format: format, date: date)))
    }
    if replacements.isEmpty {
        return (text, entities)
    }

    let source = text as NSString
    var result = ""
    var cursor = 0
    for replacement in replacements {
        let lower = max(cursor, min(replacement.range.lowerBound, source.length))
        let upper = max(lower, min(replacement.range.upperBound, source.length))
        result += source.substring(with: NSRange(location: cursor, length: lower - cursor))
        result += replacement.text
        cursor = upper
    }
    result += source.substring(from: cursor)

    func mapOffset(_ offset: Int, isUpperBound: Bool) -> Int {
        var shift = 0
        for replacement in replacements {
            let newLength = (replacement.text as NSString).length
            if offset >= replacement.range.upperBound {
                shift += newLength - replacement.range.count
            } else if offset > replacement.range.lowerBound {
                return replacement.range.lowerBound + shift + (isUpperBound ? newLength : 0)
            } else {
                break
            }
        }
        return offset + shift
    }

    let mapped = entities.map { entity -> MessageTextEntity in
        let lower = mapOffset(entity.range.lowerBound, isUpperBound: false)
        let upper = mapOffset(entity.range.upperBound, isUpperBound: true)
        return MessageTextEntity(range: lower ..< max(lower, upper), type: entity.type)
    }
    return (result, mapped)
}
