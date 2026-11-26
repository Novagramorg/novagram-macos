import Foundation
import SwiftSignalKit
import TelegramContext

public struct PhoneNumberUtilsHooks {
    public let currentCountriesConfiguration: (any AccountContextProtocol) -> Atomic<CountriesConfiguration>

    public init(currentCountriesConfiguration: @escaping (any AccountContextProtocol) -> Atomic<CountriesConfiguration>) {
        self.currentCountriesConfiguration = currentCountriesConfiguration
    }

    private static var _shared: PhoneNumberUtilsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PhoneNumberUtilsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PhoneNumberUtilsHooks.install must be called before phone numbers are formatted with an account context")
        return .placeholder
    }

    public static func install(_ hooks: PhoneNumberUtilsHooks) {
        assert(Thread.isMainThread, "PhoneNumberUtilsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PhoneNumberUtilsHooks(currentCountriesConfiguration: { _ in
        Atomic(value: CountriesConfiguration(countries: []))
    })
}
