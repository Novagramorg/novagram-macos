import Foundation
import TelegramCore

public struct AutoarchiveConfiguration : Equatable {
    public let autoarchive_setting_available: Bool
    public init(autoarchive_setting_available: Bool) {
        self.autoarchive_setting_available = autoarchive_setting_available
    }
    public static func with(appConfiguration: AppConfiguration) -> AutoarchiveConfiguration {
        return AutoarchiveConfiguration(autoarchive_setting_available: appConfiguration.data?["autoarchive_setting_available"] as? Bool ?? false)
    }
}
