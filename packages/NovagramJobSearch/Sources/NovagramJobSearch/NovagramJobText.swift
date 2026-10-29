import Foundation

public enum NovagramJobText {
    static let apostropheVariants: Set<Unicode.Scalar> = ["\u{02BB}", "\u{02BC}", "\u{2018}", "\u{2019}", "`", "\u{00B4}", "\u{2032}"]

    public static func unifiedApostrophes(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { apostropheVariants.contains($0) }) else {
            return text
        }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(apostropheVariants.contains(scalar) ? "'" : scalar)
        }
        return String(scalars)
    }

    public static func normalized(_ text: String) -> String {
        let folded = unifiedApostrophes(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(apostropheVariants.contains(scalar) ? "'" : scalar)
        }
        return String(scalars)
    }

    public static func isLatinLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (scalar.value >= 0x41 && scalar.value <= 0x5A) || (scalar.value >= 0x61 && scalar.value <= 0x7A)
    }

    public static func isCyrillicLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return scalar.value >= 0x0400 && scalar.value <= 0x04FF
    }

    private static let latinSingle: [Character: String] = [
        "a": "а", "b": "б", "c": "ц", "d": "д", "e": "е", "f": "ф", "g": "г", "h": "ҳ", "i": "и",
        "j": "ж", "k": "к", "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "q": "қ", "r": "р",
        "s": "с", "t": "т", "u": "у", "v": "в", "w": "в", "x": "х", "y": "й", "z": "з", "'": "ъ"
    ]

    private static let latinPairs: [String: String] = [
        "sh": "ш", "ch": "ч", "o'": "ў", "g'": "ғ", "ya": "я", "yu": "ю", "yo": "ё", "ye": "е", "ts": "ц"
    ]

    private static let cyrillicMap: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "j", "з": "z",
        "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
        "с": "s", "т": "t", "у": "u", "ф": "f", "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh",
        "ъ": "'", "ы": "i", "ь": "", "э": "e", "ю": "yu", "я": "ya", "ў": "o'", "қ": "q", "ғ": "g'",
        "ҳ": "h", "і": "i"
    ]

    private static func applyCase(_ output: String, uppercase: Bool) -> String {
        guard uppercase, let first = output.first else { return output }
        return String(first).uppercased() + output.dropFirst()
    }

    private static func isWordStart(_ characters: [Character], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return !(previous.isLetter || previous == "'")
    }

    public static func uzbekLatinToCyrillic(_ text: String) -> String {
        let characters = Array(unifiedApostrophes(text))
        var result = ""
        result.reserveCapacity(characters.count * 2)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let lower = Character(character.lowercased())
            let uppercase = character.isUppercase
            if index + 1 < characters.count {
                let next = Character(characters[index + 1].lowercased())
                let pair = String([lower, next])
                let followedByApostrophe = index + 2 < characters.count && characters[index + 2] == "'"
                if let mapped = latinPairs[pair], !(pair == "yo" && followedByApostrophe) {
                    result += applyCase(mapped, uppercase: uppercase)
                    index += 2
                    continue
                }
            }
            if lower == "e" && isWordStart(characters, index) {
                result += applyCase("э", uppercase: uppercase)
            } else if lower == "'" {
                let afterLetter = index > 0 && characters[index - 1].isLetter
                let beforeLetter = index + 1 < characters.count && characters[index + 1].isLetter
                result += afterLetter && beforeLetter ? "ъ" : "'"
            } else if let mapped = latinSingle[lower] {
                result += applyCase(mapped, uppercase: uppercase)
            } else {
                result.append(character)
            }
            index += 1
        }
        return result
    }

    public static func uzbekCyrillicToLatin(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(characters.count * 2)
        for (index, character) in characters.enumerated() {
            let lower = Character(character.lowercased())
            let uppercase = character.isUppercase
            if lower == "е" {
                let previous: Character? = index > 0 ? Character(characters[index - 1].lowercased()) : nil
                let afterVowelOrSign = previous.map { "аеёиоуўэюяъь".contains($0) } ?? false
                let output = isWordStart(characters, index) || afterVowelOrSign ? "ye" : "e"
                result += applyCase(output, uppercase: uppercase)
            } else if let mapped = cyrillicMap[lower] {
                result += applyCase(mapped, uppercase: uppercase)
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func otherScriptVariant(_ term: String) -> String? {
        var hasLatin = false
        var hasCyrillic = false
        for character in term {
            if isLatinLetter(character) {
                hasLatin = true
            } else if isCyrillicLetter(character) {
                hasCyrillic = true
            } else if character.isLetter || character.isNumber || character == "+" || character == "#" {
                return nil
            }
        }
        if hasLatin && !hasCyrillic {
            return uzbekLatinToCyrillic(term)
        }
        if hasCyrillic && !hasLatin {
            return uzbekCyrillicToLatin(term)
        }
        return nil
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        return character.isLetter || character.isNumber || character == "'" || character == "_"
    }

    static func containsAtWordStart(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, options: .literal, range: searchRange) {
            if found.lowerBound == haystack.startIndex || !isWordCharacter(haystack[haystack.index(before: found.lowerBound)]) {
                return true
            }
            searchRange = haystack.index(after: found.lowerBound)..<haystack.endIndex
        }
        return false
    }
}
