import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif


public final class ApplicationSpecificBoolNotice: Codable {
    public init() {
    }
    
    public init(from decoder: Decoder) throws {
    }
    
    public func encode(to encoder: Encoder) throws {
    }
}

public final class ApplicationSpecificVariantNotice: Codable {
    public let value: Bool
    
    public init(value: Bool) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.value = try container.decode(Int32.self, forKey: "v") != 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.value ? 1 : 0) as Int32, forKey: "v")
    }
}

public final class ApplicationSpecificCounterNotice: Codable {
    public let value: Int32
    
    public init(value: Int32) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.value = try container.decode(Int32.self, forKey: "v")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.value, forKey: "v")
    }
}

public final class ApplicationSpecificTimestampNotice: Codable {
    public let value: Int32
    
    public init(value: Int32) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.value = try container.decode(Int32.self, forKey: "v")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.value, forKey: "v")
    }
}

public final class ApplicationSpecificTimestampAndCounterNotice: Codable {
    public let counter: Int32
    public let timestamp: Int32
    
    public init(counter: Int32, timestamp: Int32) {
        self.counter = counter
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.counter = try container.decode(Int32.self, forKey: "v")
        self.timestamp = try container.decode(Int32.self, forKey: "t")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.counter, forKey: "v")
        try container.encode(self.timestamp, forKey: "t")
    }
}

public final class ApplicationSpecificInt64ArrayNotice: Codable {
    public let values: [Int64]
    
    public init(values: [Int64]) {
        self.values = values
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.values = try container.decode([Int64].self, forKey: "v")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.values, forKey: "v")
    }
}

public final class ApplicationSpecificMessageIdSetNotice: Codable {
    private static let maxSize = 10000

    public var values: Set<String>

    public init(values: Set<String>) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.values = try container.decode(Set<String>.self, forKey: "v")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.values, forKey: "v")
    }

    public func add(_ messageIds: [MessageId]) {
        for id in messageIds {
            values.insert("\(id.peerId.toInt64())_\(id.id)")
        }
        if values.count > Self.maxSize {
            let excess = values.count - Self.maxSize
            values = Set(values.dropFirst(excess))
        }
    }

    public func contains(_ messageId: MessageId) -> Bool {
        return values.contains("\(messageId.peerId.toInt64())_\(messageId.id)")
    }

    public func asMessageIds() -> [MessageId] {
        return values.compactMap { key -> MessageId? in
            let parts = key.split(separator: "_")
            guard parts.count == 2,
                  let peerId = Int64(parts[0]),
                  let id = Int32(parts[1]) else {
                return nil
            }
            return MessageId(peerId: PeerId(peerId), namespace: Namespaces.Message.Cloud, id: id)
        }
    }
}

private func noticeNamespace(namespace: Int32) -> ValueBoxKey {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: namespace)
    return key
}

private func noticeKey(peerId: PeerId, key: Int32) -> ValueBoxKey {
    let v = ValueBoxKey(length: 8 + 4)
    v.setInt64(0, value: peerId.toInt64())
    v.setInt32(8, value: key)
    return v
}

private enum ApplicationSpecificGlobalNotice: Int32 {
    case value = 0
    case dismissedBirthdayPremiumGifts = 1
    case playedMessageEffects = 2
    case playedMessageEffectsSet = 3
    case walletGramTooltip = 90

    public var key: ValueBoxKey {
        let v = ValueBoxKey(length: 4)
        v.setInt32(0, value: self.rawValue)
        return v
    }
}


private struct ApplicationSpecificNoticeKeys {
    private static let globalNamespace: Int32 = 2
    private static let botPaymentLiabilityNamespace: Int32 = 1
    
    public static func botPaymentLiabilityNotice(peerId: PeerId) -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: botPaymentLiabilityNamespace), key: noticeKey(peerId: peerId, key: 0))
    }
    public static func dismissedBirthdayPremiumGifts() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.dismissedBirthdayPremiumGifts.key)
    }
    public static func playedMessageEffects() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.playedMessageEffects.key)
    }
    public static func walletGramTooltip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.walletGramTooltip.key)
    }
    public static func playedMessageEffectsSet() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.playedMessageEffectsSet.key)
    }
}

public struct ApplicationSpecificNotice {
    public static func getWalletGramTooltip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction in
            transaction.getNotice(ApplicationSpecificNoticeKeys.walletGramTooltip())?.get(ApplicationSpecificCounterNotice.self)?.value ?? 0
        }
    }

    public static func incrementWalletGramTooltip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction in
            let count = transaction.getNotice(ApplicationSpecificNoticeKeys.walletGramTooltip())?.get(ApplicationSpecificCounterNotice.self)?.value ?? 0
            if let entry = CodableEntry(ApplicationSpecificCounterNotice(value: count + 1)) {
                transaction.setNotice(ApplicationSpecificNoticeKeys.walletGramTooltip(), entry)
            }
        }
    }

    public static func resetWalletGramTooltip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction in
            transaction.setNotice(ApplicationSpecificNoticeKeys.walletGramTooltip(), nil)
        }
    }

    public static func getBotPaymentLiability(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.botPaymentLiabilityNotice(peerId: peerId))?.get(ApplicationSpecificBoolNotice.self) {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setBotPaymentLiability(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            if let entry = CodableEntry(ApplicationSpecificBoolNotice()) {
                transaction.setNotice(ApplicationSpecificNoticeKeys.botPaymentLiabilityNotice(peerId: peerId), entry)
            }
        }
    }
    
    public static func dismissedBirthdayPremiumGifts(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<[Int64]?, NoError> {
        return accountManager.noticeEntry(key: ApplicationSpecificNoticeKeys.dismissedBirthdayPremiumGifts())
        |> map { view -> [Int64]? in
            if let value = view.value?.get(ApplicationSpecificInt64ArrayNotice.self) {
                return value.values
            } else {
                return nil
            }
        }
    }
    
    public static func playedMessageEffects(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<[MessageId]?, NoError> {
        return accountManager.noticeEntry(key: ApplicationSpecificNoticeKeys.playedMessageEffectsSet())
        |> map { view -> [MessageId]? in
            if let value = view.value?.get(ApplicationSpecificMessageIdSetNotice.self) {
                return value.asMessageIds()
            } else {
                return nil
            }
        }
    }

    public static func addPlayedMessageEffects(accountManager: AccountManager<TelegramAccountManagerTypes>, values: [MessageId]) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            let current = transaction.getNotice(ApplicationSpecificNoticeKeys.playedMessageEffectsSet())?.get(ApplicationSpecificMessageIdSetNotice.self) ?? ApplicationSpecificMessageIdSetNotice(values: [])
            current.add(values)
            if let entry = CodableEntry(current) {
                transaction.setNotice(ApplicationSpecificNoticeKeys.playedMessageEffectsSet(), entry)
            }
        }
    }

}
