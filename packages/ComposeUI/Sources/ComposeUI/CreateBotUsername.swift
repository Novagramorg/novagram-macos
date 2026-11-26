import Foundation
import TelegramCore
import Localization

struct CreateBotUsernameEndings: Equatable {
    static let freeEnding = "bot"
    static let appConfigurationKey = "bot_allowed_suffixes"

    let premium: [String]

    init(configuredValue value: Any?) {
        var premium: [String] = []
        for case let item as String in (value as? [Any]) ?? [] {
            let ending = item.lowercased()
            if !ending.isEmpty, ending != CreateBotUsernameEndings.freeEnding, !premium.contains(ending) {
                premium.append(ending)
            }
        }
        self.premium = premium
    }

    init(appConfiguration: AppConfiguration) {
        self.init(configuredValue: appConfiguration.data?[CreateBotUsernameEndings.appConfigurationKey])
    }

    var all: [String] {
        return [CreateBotUsernameEndings.freeEnding] + self.premium
    }
}

struct CreateBotUsername: Equatable {
    enum ValidationError: Equatable {
        case unsupportedCharacters
        case startsWithNumber
        case tooShort
        case tooLong
    }

    static let minLength = 5
    static let maxLength = 32
    static let defaultSuffixLimit: Int32 = 2

    let typedText: String
    let ending: String
    let appendedSuffix: String?

    init(typedText: String, endings: CreateBotUsernameEndings) {
        self.typedText = typedText
        let lowercasedText = typedText.lowercased()
        let candidates = endings.all.sorted(by: { $0.count > $1.count })
        if let ending = candidates.first(where: { lowercasedText.count > $0.count && lowercasedText.hasSuffix($0) }) {
            self.ending = ending
            self.appendedSuffix = nil
        } else {
            self.ending = CreateBotUsernameEndings.freeEnding
            self.appendedSuffix = CreateBotUsernameEndings.freeEnding
        }
    }

    var username: String {
        return self.typedText + (self.appendedSuffix ?? "")
    }

    var requiresPremium: Bool {
        return self.ending != CreateBotUsernameEndings.freeEnding
    }

    var validationError: ValidationError? {
        let username = self.username
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        if !username.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) {
            return .unsupportedCharacters
        }
        if let first = username.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
            return .startsWithNumber
        }
        if username.count < CreateBotUsername.minLength {
            return .tooShort
        }
        if username.count > CreateBotUsername.maxLength {
            return .tooLong
        }
        return nil
    }
}

enum CreateBotUsernameStatus: Equatable {
    case checking
    case valid
    case invalid
    case taken
    case suffixNotAllowed
    case premiumRequired
    case suffixLimitExceeded(limit: Int32?)

    init(_ availability: BotUsernameAvailability) {
        switch availability {
        case .available:
            self = .valid
        case .invalid, .purchaseAvailable:
            self = .invalid
        case .taken:
            self = .taken
        case .suffixNotAllowed:
            self = .suffixNotAllowed
        case .premiumRequired:
            self = .premiumRequired
        case let .suffixLimitExceeded(limit):
            self = .suffixLimitExceeded(limit: limit)
        }
    }

    static func decidedLocally(for username: CreateBotUsername, isPremium: Bool) -> CreateBotUsernameStatus? {
        if username.validationError != nil {
            return .invalid
        }
        if username.requiresPremium && !isPremium {
            return .premiumRequired
        }
        return nil
    }
}

enum CreateBotUsernameFooter: Equatable {
    case hint
    case hintError
    case validationError(CreateBotUsername.ValidationError)
    case invalid
    case taken
    case premiumRequired(ending: String)
    case suffixLimitExceeded(limit: Int32?)

    init(username: CreateBotUsername, status: CreateBotUsernameStatus?) {
        if let validationError = username.validationError {
            self = .validationError(validationError)
            return
        }
        switch status ?? .valid {
        case .checking, .valid:
            self = .hint
        case .invalid:
            self = .invalid
        case .taken:
            self = .taken
        case .suffixNotAllowed:
            self = .hintError
        case .premiumRequired:
            self = .premiumRequired(ending: username.ending)
        case let .suffixLimitExceeded(limit):
            self = .suffixLimitExceeded(limit: limit)
        }
    }
}

func createBotCanCreate(name: String, username: CreateBotUsername, status: CreateBotUsernameStatus?) -> Bool {
    return !name.isEmpty && username.validationError == nil && status == .valid
}

func createBotUsernameEndingsList(_ endings: [String]) -> String {
    let items = endings.map { "'\($0)'" }
    guard let last = items.last else {
        return ""
    }
    if items.count == 1 {
        return last
    }
    return strings().createBotUsernameEndingsOr(items.dropLast().joined(separator: ", "), last)
}

func createBotUsernamePremiumHint(endings: CreateBotUsernameEndings, premiumLink: Bool) -> String? {
    if endings.premium.isEmpty {
        return nil
    }
    let premium = premiumLink ? strings().createBotUsernamePremiumLink : strings().createBotUsernamePremium
    return strings().createBotUsernamePremiumHint(createBotUsernameEndingsList([CreateBotUsernameEndings.freeEnding]), createBotUsernameEndingsList(endings.premium), premium)
}

func createBotUsernamePremiumRequiredText(ending: String) -> String {
    return strings().createBotUsernamePremiumRequired(createBotUsernameEndingsList([ending]))
}

func createBotUsernameSuffixLimitText(limit: Int32?, endings: CreateBotUsernameEndings) -> String {
    let value = limit ?? CreateBotUsername.defaultSuffixLimit
    let count = strings().createBotUsernameCountOther(Int(value))
    return strings().createBotUsernameSuffixLimit(count, createBotUsernameEndingsList(endings.premium))
}
