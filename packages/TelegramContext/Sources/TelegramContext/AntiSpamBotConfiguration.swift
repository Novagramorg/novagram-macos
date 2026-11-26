import Foundation
import TelegramCore

public struct AntiSpamBotConfiguration {
    public static var defaultValue: AntiSpamBotConfiguration {
        return AntiSpamBotConfiguration(antiSpamBotId: nil, group_size_min: 100)
    }

    public let antiSpamBotId: EnginePeer.Id?
    public let group_size_min: Int32
    fileprivate init(antiSpamBotId: EnginePeer.Id?, group_size_min: Int32) {
        self.antiSpamBotId = antiSpamBotId
        self.group_size_min = group_size_min
    }

    public static func with(appConfiguration: AppConfiguration) -> AntiSpamBotConfiguration {
        if let data = appConfiguration.data, let string = data["telegram_antispam_user_id"] as? String, let value = Int64(string) {
            let group_size_min: Int32

            if let string = data["telegram_antispam_group_size_min"] as? String, let value = Int32(string) {
                group_size_min = value
            } else {
                group_size_min = 100
            }

            return AntiSpamBotConfiguration(antiSpamBotId: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(value)), group_size_min: group_size_min)
        } else {
            return .defaultValue
        }
    }
}
