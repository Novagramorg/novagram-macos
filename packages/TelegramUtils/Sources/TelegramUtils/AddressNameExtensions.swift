import Foundation
import TelegramCore
import Postbox
import Localization

public extension AddressNameFormatError {
    var description:String {
        switch self {
        case .startsWithUnderscore:
            return strings().errorUsernameUnderscopeStart
        case .endsWithUnderscore:
            return strings().errorUsernameUnderscopeEnd
        case .startsWithDigit:
            return strings().errorUsernameNumberStart
        case .invalidCharacters:
            return strings().errorUsernameInvalid
        case .tooShort:
            return strings().errorUsernameMinimumLength
        }
    }
}

public extension AddressNameAvailability {

    enum Target {
        case username
        case channel
    }
    
    func description(for username: String, target: Target) -> String {
        switch self {
        case .available:
            return strings().usernameSettingsAvailable(username)
        case .invalid:
            return strings().errorUsernameInvalid
        case .taken:
            return strings().errorUsernameAlreadyTaken
        case .purchaseAvailable:
            switch target {
            case .username:
                return strings().usernameUsernamePurchaseAvailable
            case .channel:
                return strings().channelUsernameUsernamePurchaseAvailable
            }
        }
    }
}

public enum AddressNameAvailabilityState : Equatable {
    case none(username: String?)
    case success(username: String?)
    case progress(username: String?)
    case fail(username: String?, formatError: AddressNameFormatError?, availability: AddressNameAvailability)
    
    public var username:String? {
        switch self {
        case let .none(username:username):
            return username
        case let .success(username:username):
            return username
        case let .progress(username:username):
            return username
        case let .fail(username, _, _):
            return username
        }
    }
}

public func ==(lhs:AddressNameAvailabilityState, rhs:AddressNameAvailabilityState) -> Bool {
    switch lhs {
    case let .none(username:lhsName):
        if case let .none(username:rhsName) = rhs, lhsName == rhsName {
            return true
        }
        return false
    case let .success(username:lhsName):
        if case let .success(username:rhsName) = rhs, lhsName == rhsName {
            return true
        }
        return false
    case let .progress(username:lhsName):
        if case let .progress(username:rhsName) = rhs, lhsName == rhsName {
            return true
        }
        return false
    case let .fail(lhsUsername, lhsFormatError, lhsAvailability):
        if case let .fail(rhsUsername, rhsFormatError, rhsAvailability) = rhs, lhsFormatError == rhsFormatError && lhsUsername == rhsUsername && lhsAvailability == rhsAvailability {
            return true
        }
        return false
    }
}
