import Foundation
import WalletContext
import TelegramTheme
import TelegramContext
import GeneralRows
import Localization

@available(macOS 10.15, *)
public struct WalletTransferPresentation {
    public struct SigningField: Equatable {
        public let name: String
        public let value: String
    }

    public enum SigningContent: Equatable {
        case text(String)
        case binary
        case message([[SigningField]])

        public var explanation: String? {
            switch self {
            case .text:
                return strings().walletTransferPresentationSignTextExplanation
            case .binary:
                return nil
            case .message:
                return strings().walletTransferPresentationSignMessageExplanation
            }
        }
    }

    public struct PreviewItem {
        public enum Kind: Equatable { case transfer, callContract, deployContract, excess, unknown }
        public enum Direction: Equatable { case incoming, outgoing }

        public let id: String
        public let kind: Kind
        public let direction: Direction?
        public let address: String?
        public let amount: String?
        public let comment: String?
        public let succeeded: Bool
        public init(id: String, kind: Kind, direction: Direction?, address: String?, amount: String?, comment: String?, succeeded: Bool) {
            self.id = id
            self.kind = kind
            self.direction = direction
            self.address = address
            self.amount = amount
            self.comment = comment
            self.succeeded = succeeded
        }
    }

    public let request: WalletContext.TonConnectOperationRequest
    public let walletState: WalletContext.State?

    public var isSigning: Bool {
        return self.request.method == .signData || self.request.method == .signMessage
    }

    public var signingContent: SigningContent? {
        switch self.request.method {
        case .sendTransaction:
            return nil
        case .signData:
            guard let signData = self.request.signData else { return .binary }
            switch signData.payload {
            case let .text(text):
                return .text(text)
            case .binary, .cell:
                return .binary
            }
        case .signMessage:
            var groups: [[SigningField]] = []
            if let validUntil = self.request.validUntil {
                groups.append([SigningField(name: "valid_until", value: String(validUntil))])
            }
            for (index, message) in self.request.messages.enumerated() {
                var fields: [SigningField] = []
                if self.request.messages.count > 1 {
                    fields.append(SigningField(name: "message", value: String(index + 1)))
                }
                fields.append(SigningField(name: "address", value: message.destination))
                fields.append(SigningField(name: "amount", value: formatTonConnectGrams(message.amountNanograms)))
                switch message.payload {
                case .empty:
                    break
                case let .comment(text):
                    fields.append(SigningField(name: "comment", value: text))
                case let .raw(boc):
                    fields.append(SigningField(name: "payload (BOC/Base64)", value: boc))
                }
                if let stateInit = message.stateInit {
                    fields.append(SigningField(name: "stateInit (BOC/Base64)", value: stateInit))
                }
                groups.append(fields)
            }
            return .message(groups)
        }
    }

    public var amountNanograms: String? {
        var total = "0"
        for message in self.request.messages {
            if message.amountNanograms == "all" { return "all" }
            guard let amount = normalizedTonConnectNanograms(message.amountNanograms) else { return nil }
            let lhs = Array(total.utf8.reversed())
            let rhs = Array(amount.utf8.reversed())
            var digits: [UInt8] = []
            var carry = 0
            for index in 0..<max(lhs.count, rhs.count) {
                let sum = (index < lhs.count ? Int(lhs[index] - 48) : 0)
                    + (index < rhs.count ? Int(rhs[index] - 48) : 0) + carry
                digits.append(UInt8(sum % 10) + 48)
                carry = sum / 10
            }
            if carry != 0 { digits.append(UInt8(carry) + 48) }
            total = String(decoding: digits.reversed(), as: UTF8.self)
        }
        return total
    }

    public var recipient: String {
        guard let message = self.request.messages.first else { return "" }
        return WalletContext.transferAddress(from: message.destination) ?? message.destination
    }

    public var recipientTitle: String? {
        guard self.request.messages.count > 1 else { return nil }
        let recipients = Set(self.request.messages.map { WalletContext.transferAddress(from: $0.destination) ?? $0.destination })
        return recipients.count == 1 ? nil : strings().walletTransferPresentationRecipientsOther(recipients.count)
    }

    public var previewItems: [PreviewItem] {
        if self.request.actions.isEmpty {
            return self.request.messages.map { message in
                let kind: PreviewItem.Kind
                let comment: String?
                switch message.payload {
                case .empty: kind = .transfer; comment = nil
                case let .comment(value): kind = .transfer; comment = value
                case .raw: kind = .callContract; comment = nil
                }
                return PreviewItem(id: message.id, kind: kind, direction: .outgoing,
                    address: WalletContext.transferAddress(from: message.destination) ?? message.destination,
                    amount: message.amountNanograms, comment: comment, succeeded: true)
            }
        }
        let walletAddress: String?
        if let state = self.walletState, case let .wallet(wallet) = state.phase {
            walletAddress = WalletContext.transferAddress(from: wallet.address)
        } else {
            walletAddress = nil
        }
        return self.request.actions.map { action in
            let kind: PreviewItem.Kind
            switch action.kind {
            case "ton_transfer": kind = .transfer
            case "call_contract": kind = .callContract
            case "contract_deploy", "deploy_contract": kind = .deployContract
            case "excess": kind = .excess
            default: kind = .unknown
            }
            let details = (try? JSONSerialization.jsonObject(with: Data(action.detailsJson.utf8))) as? [String: Any] ?? [:]
            let source = (details["source"] as? String).flatMap { WalletContext.transferAddress(from: $0) }
            let destination = (details["destination"] as? String).flatMap { WalletContext.transferAddress(from: $0) }
            let direction: PreviewItem.Direction?
            if let walletAddress, source == walletAddress { direction = .outgoing }
            else if let walletAddress, destination == walletAddress { direction = .incoming }
            else { direction = nil }
            let address = direction == .incoming ? source : destination
            let amount = action.kind == "ton_transfer"
                ? (details["value"] as? String).flatMap(normalizedTonConnectNanograms) : nil
            return PreviewItem(id: action.id, kind: kind, direction: direction,
                address: address ?? action.accounts.first.flatMap { WalletContext.transferAddress(from: $0) },
                amount: amount, comment: details["comment"] as? String, succeeded: action.succeeded)
        }
    }

    public var submissionText: String? {
        guard self.request.method == .signMessage else { return nil }
        if let validUntil = self.request.validUntil {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = appAppearance.locale
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let date = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(validUntil)))
            return strings().walletTransferPresentationSubmitUntil(date)
        }
        return strings().walletTransferPresentationWillSubmit
    }

    public var feeText: String {
        guard let fee = self.request.feeNanograms else {
            return ""
        }
        let formattedFee = formatTonConnectNanograms(fee)
        let prefix = strings().walletTransferPresentationFee
        if let feeValue = Int64(fee), let fiatRate = self.walletState?.fiat.selectedRate {
            let currency = self.walletState?.fiat.selectedCurrency ?? .usd
            let fiatValue = Double(feeValue) / 1_000_000_000.0 * fiatRate.unitsPerGram
            let fiatFee: String
            if fiatValue > 0.0, fiatValue < 0.01 {
                fiatFee = "<\(currency.symbol)0\(walletDecimalSeparator)01"
            } else {
                fiatFee = formatTonFiatValue(feeValue, rate: fiatRate.unitsPerGram, currencySymbol: currency.symbol, maxDecimalPositions: 2)
            }
            return "\(prefix): \(formattedFee) (\(fiatFee))."
        } else {
            return "\(prefix): \(formattedFee)."
        }
    }

    @available(macOS 10.15, *)
    public init(request: WalletContext.TonConnectOperationRequest, walletState: WalletContext.State?) {
        self.request = request
        self.walletState = walletState
    }
}

private func normalizedTonConnectNanograms(_ value: String) -> String? {
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    let digits = String(value.drop(while: { $0 == "0" }))
    return digits.isEmpty ? "0" : digits
}

public func formatTonConnectNanograms(_ value: String) -> String {
    if value == "all" { return strings().walletTransferPresentationAllBalance }
    guard let digits = normalizedTonConnectNanograms(value) else { return strings().walletTransferPresentationUnavailable }
    if let value = Int64(digits) {
        return walletGramsUnitText(formatTonAmountText(value, maxDecimalPositions: 9))
    }
    let split = digits.index(digits.endIndex, offsetBy: -9)
    let integer = digits[..<split]
    let fraction = String(digits[split...].reversed().drop(while: { $0 == "0" }).reversed())
    return fraction.isEmpty ? String(integer) : "\(integer)\(Locale.current.decimalSeparator ?? ".")\(fraction)"
}

public func formatTonConnectGrams(_ value: String) -> String {
    let amount = formatTonConnectNanograms(value)
    if let digits = normalizedTonConnectNanograms(value), Int64(digits) == nil {
        return walletGramsUnitText(amount)
    }
    return amount
}

public func walletTransferShortAddress(_ address: String) -> String {
    guard address.count > 8 else { return address }
    return "\(address.prefix(4))...\(address.suffix(4))"
}
