import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import WalletContext

public struct WalletTonAddressActions {
    public let owner: EnginePeer?
    public let send: () -> Void
    public let openExplorer: () -> Void
}

@available(macOS 10.15, *)
public func walletTonAddressActions(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, address: String) -> Signal<WalletTonAddressActions?, NoError> {
    guard WalletContext.transferAddress(from: address) != nil else {
        return .single(nil)
    }
    return walletAddressOwner(context: context, address: address)
    |> timeout(2.0, queue: .mainQueue(), alternate: .single(nil))
    |> map { owner in
        return WalletTonAddressActions(owner: owner?.peer, send: {
            let window = context.window
            switch walletContext.stateValue.phase {
            case .empty, .creating, .failed:
                showWallet(context: context, environment: environment, walletContext: walletContext, for: window)
            case .restoring, .wallet:
                if let owner {
                    showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, peer: owner.peer._asPeer(), address: address, publicKey: owner.publicKey, completed: walletOpenRecipientChat(environment: environment, window: window, peerId: owner.peer.id)), for: window)
                } else {
                    showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, initialAddress: address), for: window)
                }
            }
        }, openExplorer: {
            let explorerUrl = WalletConfiguration.with(appConfiguration: context.appConfiguration).explorerUrl
            let baseUrl = explorerUrl.hasSuffix("/") ? explorerUrl : explorerUrl + "/"
            guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) else {
                return
            }
            environment.openExternalURL(baseUrl + encodedAddress)
        })
    }
}
