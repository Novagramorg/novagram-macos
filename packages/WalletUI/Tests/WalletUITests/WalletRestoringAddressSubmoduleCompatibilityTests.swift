import XCTest
import AppKit
import WalletContext
@testable import WalletUI

final class WalletRestoringAddressSubmoduleCompatibilityTests: XCTestCase {
    private let walletAddress = WalletContext.transferAddress(from: "0:" + String(repeating: "1a", count: 32))!
    private let otherAddress = "EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N"

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func collapsed(_ text: String) -> String {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func assertContains(_ text: String, _ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        let text = collapsed(text)
        for item in lines {
            XCTAssertTrue(text.contains(collapsed(item)), item, file: file, line: line)
        }
    }

    private func submoduleStrings() throws -> [String: String] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private func state(_ phase: WalletContext.Phase, walletAddress: String?) -> WalletContext.State {
        return WalletContext.State(
            phase: phase,
            walletAddress: walletAddress,
            balance: .idle,
            transactions: WalletContext.TransactionsState(items: [], offset: 0, canLoadMore: false, isLoadingMore: false, error: nil),
            pendingTransfers: [],
            activeOperation: nil
        )
    }

    func testStateKeepsTheSavedAddressOnlyWhileRestoring() {
        let info = WalletContext.WalletInfo(address: walletAddress, publicKey: "key")
        XCTAssertEqual(state(.restoring, walletAddress: walletAddress).walletAddress, walletAddress)
        XCTAssertNil(state(.restoring, walletAddress: nil).walletAddress)
        XCTAssertEqual(state(.wallet(info), walletAddress: nil).walletAddress, walletAddress)
        XCTAssertEqual(state(.wallet(info), walletAddress: otherAddress).walletAddress, walletAddress)
        for phase: WalletContext.Phase in [.creating, .empty, .failed(.corrupted)] {
            XCTAssertNil(state(phase, walletAddress: walletAddress).walletAddress, "\(phase)")
        }
    }

    func testSelfTransferUsesTheSavedAddressLikeSubmodule() {
        let info = WalletContext.WalletInfo(address: walletAddress, publicKey: "key")
        let phases: [(WalletContext.Phase?, String?)] = [
            (.restoring, walletAddress),
            (.restoring, nil),
            (.wallet(info), walletAddress),
            (nil, nil)
        ]
        for (phase, address) in phases {
            for recipient in [walletAddress, "0:" + String(repeating: "1a", count: 32), otherAddress, "ton://transfer/\(walletAddress)?amount=1"] {
                var sendState = WalletSendState()
                sendState.walletPhase = phase
                sendState.walletAddress = address
                sendState.resolved = .init(address: recipient, displayName: nil)
                XCTAssertEqual(walletSendIsSelfTransfer(sendState), WalletContext.isSelfTransfer(recipient: recipient, walletAddress: address), "\(String(describing: phase)) \(recipient)")
            }
        }
        XCTAssertTrue(WalletContext.isSelfTransfer(recipient: "0:" + String(repeating: "1a", count: 32), walletAddress: walletAddress))
        var restoring = WalletSendState()
        restoring.walletPhase = .restoring
        restoring.walletAddress = walletAddress
        restoring.resolved = .init(address: walletAddress, displayName: nil)
        XCTAssertTrue(walletSendIsSelfTransfer(restoring))
    }

    func testWalletHomeUsesTheSavedAddressLikeSubmodule() throws {
        assertContains(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletScreen/Sources/WalletScreen.swift"), [
            "private var walletAddress: String? { return self.walletState?.walletAddress }",
            "guard let walletAddress = self.walletAddress else { return }",
            "address: walletAddress, appeared: { [weak self, weak walletContext] in guard let self, let walletContext, self.walletContext === walletContext, self.walletAddress == walletAddress else { return }",
            "self.walletAddress != nil, !self.isResolvingSigningAccess else { return } guard let walletInfo = self.walletInfo else { self.routeToSend(address: address) return }",
            "address: walletAddress ?? \"\",",
            "isEnabled: walletAddress != nil, action: { [weak self] in self?.openReceive() }",
            "isEnabled: walletAddress != nil && !self.isResolvingSigningAccess,",
            "walletAddress: walletAddress, animatesPendingTransfer:"
        ])
        assertContains(try source("packages/WalletUI/Sources/WalletUI/WalletController.swift"), [
            "let address = state.walletState?.walletAddress ?? \"\"",
            "let actionsEnabled = state.walletState?.walletAddress != nil",
            "leftEnabled: actionsEnabled, rightEnabled: actionsEnabled && !isResolvingSigningAccess,",
            "guard let address = walletContext.stateValue.walletAddress else { return }",
            "address: address, appeared: { guard walletContext.stateValue.walletAddress == address else { return } showTransactions() }",
            "case .restoring where walletContext.stateValue.walletAddress != nil: abandonRestoration() showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, transferAnimation: transferAnimation), for: context.window, morphSource: morphSource)",
            "walletAddress: cardData.address, transferAnimation: transferAnimation,",
            "arguments.gramTooltip.update(cardView: cardView, address: cardData.address)"
        ])
    }

    func testPreviousWalletsReloadLikeSubmodule() throws {
        assertContains(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletScreen/Sources/WalletScreen.swift"), [
            "let previousWalletAddress = self.walletAddress",
            "if previousPhase != walletState.phase || previousWalletAddress != walletState.walletAddress { if previousWalletAddress != walletState.walletAddress { self.previousWalletsBalance = 0 } self.reloadPreviousWallets() }"
        ])
        assertContains(try source("packages/WalletUI/Sources/WalletUI/WalletController.swift"), [
            "let previousWalletState = stateValue.with { $0.walletState }",
            "let walletAddressChanged = previousWalletState != nil && previousWalletState?.walletAddress != walletState.walletAddress",
            "let reloadsPreviousWallets = walletAddressChanged || (previousWalletState != nil && previousWalletState?.phase != walletState.phase)",
            "if walletAddressChanged { current.previousWalletsBalance = 0 }",
            "if reloadsPreviousWallets { refreshPreviousWalletsBalanceImpl?() }",
            "refreshPreviousWalletsBalanceImpl = refreshPreviousWalletsBalance refreshPreviousWalletsBalance()"
        ])
        assertContains(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletSettingsScreen/Sources/WalletSettingsScreen.swift"), [
            "let previousWalletAddress = self.walletState?.walletAddress",
            "if previousPhase != walletState.phase || previousWalletAddress != walletState.walletAddress, self.isVisible { self.reloadPreviousWallets() }"
        ])
        assertContains(try source("packages/WalletUI/Sources/WalletUI/WalletSettingsController.swift"), [
            "if previousWalletState.phase != walletState.phase || previousWalletState.walletAddress != walletState.walletAddress { reloadPreviousWallets() }"
        ])
        assertContains(try source("submodules/telegram-ios/submodules/WalletContext/Sources/WalletOperations.swift"), [
            "guard let walletAddress = self.currentState.walletAddress else { return wallets }"
        ])
    }

    func testSendFormWaitsForTheWalletLikeSubmodule() throws {
        assertContains(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletSendScreen/Sources/WalletSendScreen.swift"), [
            "self.walletAddress = walletState.walletAddress",
            "self.walletIsLoading = self.walletInfo == nil || walletState.balance.currentValue == nil",
            "return WalletContext.isSelfTransfer(recipient: self.recipientAddress, walletAddress: self.walletAddress)"
        ])
        assertContains(try source("packages/WalletUI/Sources/WalletUI/WalletSendController.swift"), [
            "current.walletPhase = walletState.phase current.walletAddress = walletState.walletAddress",
            "let hasWallet: Bool if case .wallet = walletState.phase { hasWallet = true } else { hasWallet = false }",
            "current.isLoading = !hasWallet || walletState.balance.currentValue == nil || (walletState.activeOperation != nil && !ownPreparation)",
            "current.isLoading = !hasWallet || (walletState.activeOperation != nil && !ownPreparation)",
            "return WalletContext.isSelfTransfer(recipient: resolved.address, walletAddress: state.walletAddress)"
        ])
    }

    func testCollectibleTopUpAlertMatchesSubmodule() throws {
        let strings = try submoduleStrings()
        XCTAssertEqual(strings["Wallet.Backup.InsufficientFundsTitle"], "Not Enough Grams")
        XCTAssertEqual(strings["Wallet.Transfer.CollectibleTopUpText"], "You need at least 0.1 Grams in your wallet to transfer an NFT. Top up your balance and try again.")
        XCTAssertEqual(strings["Wallet.Backup.TopUp"], "Top Up")
        XCTAssertEqual(strings["Common.Cancel"], "Cancel")
        assertContains(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletTransactionScreen/Sources/WalletTransactionScreen.swift"), [
            "case .insufficientBalance where self.previewSource?.collectible != nil: title = strings.Wallet_Backup_InsufficientFundsTitle text = strings.Wallet_Transfer_CollectibleTopUpText actions = [ TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}), TextAlertAction(type: .defaultAction, title: strings.Wallet_Backup_TopUp, action: {",
            "case let .wallet(info) = walletContext.stateValue.phase else { return } controller.push(component.context.sharedContext.makeWalletReceiveScreen( context: component.context, address: info.address ))"
        ])
        let mac = macEnglishStrings()
        XCTAssertEqual(mac["Wallet.TransactionController.NotEnoughGramsTitle"], strings["Wallet.Backup.InsufficientFundsTitle"])
        XCTAssertEqual(mac["Wallet.TransactionController.CollectibleTopUpInfo"], strings["Wallet.Transfer.CollectibleTopUpText"])
        XCTAssertEqual(mac["Wallet.TransactionController.TopUp"], strings["Wallet.Backup.TopUp"])
        XCTAssertEqual(mac["Wallet.TransactionController.Cancel"], strings["Common.Cancel"])
        let actual = try source("packages/WalletUI/Sources/WalletUI/WalletTransactionController.swift")
        assertContains(actual, [
            "case .insufficientBalance where subjectCollectible != nil: environment.verifyAlert(for: context.window, header: strings().walletTransactionControllerNotEnoughGramsTitle, information: strings().walletTransactionControllerCollectibleTopUpInfo, ok: strings().walletTransactionControllerTopUp, cancel: strings().walletTransactionControllerCancel, successHandler: { _ in",
            "guard case let .wallet(info) = walletContext.stateValue.phase else { return } showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address), for: context.window) }) return"
        ])
        assertContains(try source("submodules/telegram-ios/submodules/WalletContext/Sources/WalletLogger.swift"), [
            "case let .InsufficientBalanceForFees(_, requestedNanograms, estimatedFeeNanograms): let amount = Int64(requestedNanograms) ?? Int64.max let fee = Int64(estimatedFeeNanograms) ?? Int64.max let (required, overflow) = amount.addingReportingOverflow(fee) return .insufficientBalance(required: overflow ? Int64.max : required)"
        ])
    }

    func testTonTransferLinksNeedAValidAddressLikeSubmodule() throws {
        assertContains(try source("submodules/telegram-ios/submodules/TelegramUI/Sources/AppDelegate.swift"), [
            "return url.scheme?.lowercased() == \"ton\" && url.host?.lowercased() == \"transfer\" && WalletContext.transferAddress(from: url.absoluteString) != nil"
        ])
        assertContains(try source("Telegram-Mac/utils/InAppLinks.swift"), [
            "case let .tonTransfer(link, data): guard let context else { return .nothing } if #available(macOS 10.15, *), WalletContext.transferAddress(from: link) == nil { return .nothing } return .tonTransfer(link: link, context: context, data: data)"
        ])
        let accepted = [
            "ton://transfer/\(otherAddress)",
            "ton://transfer/\(otherAddress)?amount=1000000000",
            "ton://transfer/\(walletAddress)?amount=1&text=hi",
            "ton://transfer/0:" + String(repeating: "2b", count: 32)
        ]
        let ignored = [
            "ton://transfer/notavalidaddress123?amount=1000000000",
            "ton://transfer/",
            "ton://transfer/EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2M",
            "ton://transfer/kQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N",
            "ton://transfer/0:" + String(repeating: "2b", count: 31)
        ]
        for link in accepted {
            XCTAssertNotNil(WalletContext.transferAddress(from: link), link)
        }
        for link in ignored {
            XCTAssertNil(WalletContext.transferAddress(from: link), link)
        }
    }
}
