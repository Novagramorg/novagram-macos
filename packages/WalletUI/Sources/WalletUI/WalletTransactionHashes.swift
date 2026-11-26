import Foundation
import WalletContext

private func serverTransactionMessageHash(id: String) -> String? {
    for marker in [":ton:in:", ":ton:out:", ":nft:in:", ":nft:out:"] {
        if let range = id.range(of: marker, options: .backwards) {
            let hash = id[range.upperBound...].split(separator: ":", maxSplits: 1).first.map(String.init)
            if let hash, !hash.isEmpty {
                return hash
            }
        }
    }
    return nil
}

public func serverTransactionNftItemAddress(id: String) -> String? {
    for marker in [":nft:in:", ":nft:out:"] {
        if let range = id.range(of: marker, options: .backwards) {
            let components = id[range.upperBound...].split(separator: ":", maxSplits: 1)
            if components.count == 2, !components[1].isEmpty {
                return String(components[1])
            }
        }
    }
    return nil
}

public func walletNormalizedTransactionHash(_ value: String) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let hexValue: Substring
    if value.hasPrefix("0x") || value.hasPrefix("0X") {
        hexValue = value.dropFirst(2)
    } else {
        hexValue = value[...]
    }
    if hexValue.count == 64 && hexValue.unicodeScalars.allSatisfy({ scalar in
        switch scalar.value {
        case 48 ... 57, 65 ... 70, 97 ... 102:
            return true
        default:
            return false
        }
    }) {
        return hexValue.lowercased()
    }

    var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 {
        base64.append("=")
    }
    guard let data = Data(base64Encoded: base64), data.count == 32 else {
        return nil
    }
    return data.map { String(format: "%02x", $0) }.joined()
}

public func walletTransactionHashMatches(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs, let rhs else {
        return false
    }
    if let lhsHex = walletNormalizedTransactionHash(lhs), let rhsHex = walletNormalizedTransactionHash(rhs) {
        return lhsHex == rhsHex
    }
    return lhs.lowercased() == rhs.lowercased()
}

@available(macOS 10.15, *)
extension WalletContext.Transaction {
    var externalMessageHash: String? {
        return serverTransactionMessageHash(id: self.id)
    }
}
