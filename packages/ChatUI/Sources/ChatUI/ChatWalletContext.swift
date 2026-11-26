import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox

public struct ChatWalletFiatRate: Equatable {
    public let unitsPerGram: Double
    public let currencySymbol: String

    public init(unitsPerGram: Double, currencySymbol: String) {
        self.unitsPerGram = unitsPerGram
        self.currencySymbol = currencySymbol
    }
}

public struct ChatWalletTonAddress {
    public let owner: EnginePeer?
    public let send: () -> Void
    public let openExplorer: () -> Void

    public init(owner: EnginePeer?, send: @escaping () -> Void, openExplorer: @escaping () -> Void) {
        self.owner = owner
        self.send = send
        self.openExplorer = openExplorer
    }
}

public struct ChatWalletTransferSnapshot {
    public enum TransactionStatus {
        case pending
        case completed
        case failed
    }

    public enum PendingStatus {
        case broadcasting
        case pending
        case submissionUnknown
        case confirmed
    }

    public struct Transaction {
        public let id: String
        public let presentationId: String
        public let transactionHash: String?
        public let isOutgoingTransfer: Bool
        public let status: TransactionStatus

        public init(id: String, presentationId: String, transactionHash: String?, isOutgoingTransfer: Bool, status: TransactionStatus) {
            self.id = id
            self.presentationId = presentationId
            self.transactionHash = transactionHash
            self.isOutgoingTransfer = isOutgoingTransfer
            self.status = status
        }
    }

    public struct PendingTransfer {
        public let id: String
        public let transactionHash: String?
        public let isCollectible: Bool
        public let status: PendingStatus

        public init(id: String, transactionHash: String?, isCollectible: Bool, status: PendingStatus) {
            self.id = id
            self.transactionHash = transactionHash
            self.isCollectible = isCollectible
            self.status = status
        }
    }

    public let transactions: [Transaction]
    public let pendingTransfers: [PendingTransfer]

    public init(transactions: [Transaction], pendingTransfers: [PendingTransfer]) {
        self.transactions = transactions
        self.pendingTransfers = pendingTransfers
    }
}

@available(macOS 10.15, *)
public protocol ChatWalletContext: AnyObject {
    var chatFiatRate: ChatWalletFiatRate? { get }
    var chatFiatRateState: Signal<ChatWalletFiatRate?, NoError> { get }
    var chatTransferSnapshot: ChatWalletTransferSnapshot { get }
    var chatTransferState: Signal<ChatWalletTransferSnapshot, NoError> { get }
    func openChatTonConnectRequest(sessionId: Int64, messageId: MessageId)
}
