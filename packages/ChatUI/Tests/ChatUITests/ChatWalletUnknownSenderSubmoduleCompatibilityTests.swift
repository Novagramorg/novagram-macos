import XCTest
import Foundation

final class ChatWalletUnknownSenderSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func collapsed(_ text: String) -> String {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func block(_ text: String, from start: String, to end: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let lower = try XCTUnwrap(text.range(of: start), start, file: file, line: line)
        let upper = try XCTUnwrap(text.range(of: end, range: lower.upperBound ..< text.endIndex), end, file: file, line: line)
        return String(text[lower.lowerBound ..< upper.lowerBound])
    }

    private func captures(_ pattern: String, in text: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return try matches.map { match in
            try String(text[XCTUnwrap(Range(match.range(at: 1), in: text), pattern, file: file, line: line)])
        }
    }

    private func submoduleStrings() throws -> [String: String] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private func macStrings() throws -> [String: String] {
        return try XCTUnwrap(NSDictionary(contentsOf: repositoryRoot().appendingPathComponent("Telegram-Mac/en.lproj/Localizable.strings")) as? [String: String])
    }

    private var chatServiceItem: String {
        get throws { try source("packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift") }
    }

    func testUnknownSenderTextsMatchSubmoduleStrings() throws {
        let strings = try submoduleStrings()
        let mac = try macStrings()
        let item = try block(chatServiceItem, from: "case let .gramTransfer(amount, peerAddress, transactionId, comment, commentEncrypted):", to: "case let .suggestedPostSuccess(amount):")

        XCTAssertEqual(item.components(separatedBy: "text = strings().chatServiceItemGramTransferUnknown(amountText)").count - 1, 1)
        let chatText = try XCTUnwrap(mac["Chat.ServiceItem.GramTransferUnknown"])
        XCTAssertEqual(chatText.replacingOccurrences(of: "%1$@", with: "%@"), strings["Notification.GramTransferUnknown"])

        XCTAssertEqual(item.components(separatedBy: "attributedString.append(string: strings().chatServiceItemGramTransferFiat(fiatText)").count - 1, 1)
        let fiatSuffix = try XCTUnwrap(mac["Chat.ServiceItem.GramTransferFiat"])
        let withFiat = chatText + fiatSuffix.replacingOccurrences(of: "%1$@", with: "%2$@")
        XCTAssertEqual(withFiat, strings["Notification.GramTransferUnknown.WithFiat"])

        XCTAssertEqual(item.components(separatedBy: "name: isUnknownSender ? strings().chatServiceItemUnknownUser : peerName,").count - 1, 1)
        XCTAssertEqual(mac["Chat.ServiceItem.UnknownUser"]?.uppercased(), strings["Notification.GramTransfer.UnknownUser"])

        let textUtils = try source("packages/MessageTextUtils/Sources/MessageTextUtils/TextUtils.swift")
        let listItem = try block(textUtils, from: "case let .gramTransfer(amount, _, _, _, _):", to: "case let .walletTonConnectRequest(")
        XCTAssertEqual(listItem.components(separatedBy: "text = strings().chatServiceGramTransferUnknown(amountText)").count - 1, 1)
        XCTAssertEqual(mac["Chat.Service.GramTransferUnknown"]?.replacingOccurrences(of: "%1$@", with: "%@"), strings["Notification.GramTransferUnknown"])
    }

    func testSubmoduleStillTreatsTheServiceChatAsUnknownSender() throws {
        let serviceStrings = collapsed(try source("submodules/telegram-ios/submodules/TelegramStringFormatting/Sources/ServiceMessageStrings.swift"))
        XCTAssertTrue(serviceStrings.contains(collapsed("""
            if message.effectivelyIncoming(accountPeerId) {
                if message.id.peerId.isTelegramNotifications {
                    text = strings.Notification_GramTransferUnknown(amountText).string
                } else {
                    text = strings.Notification_GramTransfer(compactAuthorName, amountText).string
                }
            } else {
            """)))

        let bubble = collapsed(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageTransferBubbleContentNode/Sources/ChatMessageTransferBubbleContentNode.swift"))
        for line in [
            "let peerName = item.message.id.peerId.isTelegramNotifications ? item.presentationData.strings.Notification_GramTransfer_UnknownUser :",
            "? (message.id.peerId.isTelegramNotifications ? strings.Notification_GramTransferUnknown_WithFiat(amountText, fiatValue) : strings.Notification_GramTransfer_WithFiat(peerName, amountText, fiatValue))",
            ": strings.Notification_GramTransfer_WithFiatYou(peerName, amountText, fiatValue)",
            "? (message.id.peerId.isTelegramNotifications ? strings.Notification_GramTransferUnknown(amountText) : strings.Notification_GramTransfer(peerName, amountText))",
            ": strings.Notification_GramTransferYou(peerName, amountText)"
        ] {
            XCTAssertTrue(bubble.contains(collapsed(line)), line)
        }

        let controller = collapsed(try source("submodules/telegram-ios/submodules/TelegramUI/Sources/ChatController.swift"))
        XCTAssertTrue(controller.contains(collapsed("""
            enginePeer.id.namespace == Namespaces.Peer.CloudUser,
               !enginePeer.id.isTelegramNotifications {
                peer = .user(enginePeer, address: peerAddress, domain: nil)
            } else if !peerAddress.isEmpty {
                peer = .address(peerAddress, domain: nil)
            } else {
                peer = .unsupported
            }
            """)))

        let peerUtils = collapsed(try source("submodules/telegram-ios/submodules/TelegramCore/Sources/Utils/PeerUtils.swift"))
        XCTAssertTrue(peerUtils.contains(collapsed("""
            var isTelegramNotifications: Bool {
                if self.namespace == Namespaces.Peer.CloudUser {
                    if self.id._internalGetInt64Value() == 777000 {
                        return true
                    }
                }
                return false
            }
            """)))
    }

    func testServiceChatChecksMatchSubmodule() throws {
        let wellKnown = try source("packages/TelegramUtils/Sources/TelegramUtils/WellKnownPeerIds.swift")
        XCTAssertTrue(wellKnown.contains("public let servicePeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))"))

        let item = collapsed(try block(chatServiceItem, from: "case let .gramTransfer(amount, peerAddress, transactionId, comment, commentEncrypted):", to: "case let .suggestedPostSuccess(amount):"))
        for line in [
            "let isUnknownSender = message.id.peerId == servicePeerId",
            "if isIncoming && isUnknownSender { text = strings().chatServiceItemGramTransferUnknown(amountText) } else if isIncoming { text = strings().chatServiceItemGramTransfer(peerName, amountText) } else { text = strings().chatServiceItemGramTransferYou(peerName, amountText) }"
        ] {
            XCTAssertTrue(item.contains(collapsed(line)), line)
        }

        let textUtils = collapsed(try source("packages/MessageTextUtils/Sources/MessageTextUtils/TextUtils.swift"))
        XCTAssertTrue(textUtils.contains(collapsed("""
            if authorId == account.peerId {
                text = strings().chatServiceGramTransferYou(peer.compactDisplayTitle, amountText)
            } else if message.id.peerId == servicePeerId {
                text = strings().chatServiceGramTransferUnknown(amountText)
            } else {
                text = strings().chatServiceGramTransfer(authorName, amountText)
            }
            """)))

        let hooks = collapsed(try source("Telegram-Mac/packages-integration/hooks/ChatHistoryUIHooksInstall.swift"))
        XCTAssertTrue(hooks.contains(collapsed("""
            if let enginePeer = data.peer, enginePeer.id.namespace == Namespaces.Peer.CloudUser, !enginePeer.id.isTelegramNotifications {
                peer = .user(enginePeer, address: data.peerAddress, domain: nil)
            } else if !data.peerAddress.isEmpty {
                peer = .address(data.peerAddress, domain: nil)
            } else {
                peer = .unsupported
            }
            """)))
    }

    func testCardAddressColorMatchesSubmodule() throws {
        let bubble = try source("submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageTransferBubbleContentNode/Sources/ChatMessageTransferBubbleContentNode.swift")
        let addressArguments = try block(bubble, from: "let addressLayoutArguments = TextNodeLayoutArguments(", to: "let (addressLayout, addressApply)")
        let submoduleColor = try captures("textColor: UIColor\\(rgb: 0x([0-9a-fA-F]+)\\)", in: addressArguments)

        let card = try source("packages/WalletUI/Sources/WalletUI/WalletCardView.swift")
        let actualColor = try captures("let addressLayout = TextViewLayout\\(\\.initialize\\(string: addressText, color: NSColor\\(rgb: 0x([0-9a-fA-F]+)\\)", in: card)

        XCTAssertEqual(submoduleColor.count, 1)
        XCTAssertEqual(actualColor.count, 1)
        XCTAssertEqual(actualColor.first?.lowercased(), submoduleColor.first?.lowercased())
    }
}
