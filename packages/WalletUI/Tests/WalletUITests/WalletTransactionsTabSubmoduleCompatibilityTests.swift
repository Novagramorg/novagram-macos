import XCTest
import Foundation

final class WalletTransactionsTabSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func collapsedSource(_ path: String) throws -> String {
        return collapsed(try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8))
    }

    private func collapsed(_ text: String) -> String {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        return text.components(separatedBy: needle).count - 1
    }

    func testSubmoduleWalletStillShowsTransactionsAfterReceiveAndCollectibleSend() throws {
        let screen = try collapsedSource("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletScreen/Sources/WalletScreen.swift")
        for snippet in [
            """
            private func showTransactions() {
                self.selectedSection = .transactions
                self.pendingTransferToReveal = nil
                self.shouldRevealLatestTransactions = true
                self.componentState?.updated(transition: .immediate)
            }
            """,
            """
            private func revealLatestTransactionsIfNeeded(firstTransactionId: String?) {
                guard self.shouldRevealLatestTransactions, self.selectedSection == .transactions else {
                    return
                }
                self.shouldRevealLatestTransactions = false
                if let firstTransactionId, let frame = self.transactionsSection.itemFrame(id: AnyHashable(firstTransactionId)) {
                    self.scrollToTransactionIfNeeded(frame: frame)
                } else {
                    self.scrollView.setContentOffset(.zero, animated: false)
                }
            }
            """,
            "self.revealLatestTransactionsIfNeeded(firstTransactionId: transactions.first?.presentationId)",
            "$0.isVisibleInWalletHistory && $0.kind != .deployContract",
            """
            appeared: { [weak self, weak walletContext] in
                guard let self, let walletContext, self.walletContext === walletContext,
                      self.walletAddress == walletAddress else {
                    return
                }
                self.showTransactions()
            }
            """,
            """
            self.suppressCollectible(address: address)
            self.showTransactions()
            """,
            """
            self.pendingTransferToReveal = id
            self.shouldRevealLatestTransactions = false
            """,
            """
            default:
                self.cancelWaltBalanceOpening()
                self.abandonRestoration()
                self.shouldRevealLatestTransactions = false
            """
        ] {
            XCTAssertTrue(screen.contains(collapsed(snippet)), snippet)
        }
        XCTAssertEqual(occurrences(of: "self.showTransactions()", in: screen), 3)
        XCTAssertEqual(occurrences(of: "self.shouldRevealLatestTransactions = false", in: screen), 5)

        let receive = try collapsedSource("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletReceiveScreen/Sources/WalletReceiveScreen.swift")
        XCTAssertTrue(receive.contains(collapsed("""
            fileprivate func completeAppearance() {
                let appeared = self.appeared
                self.appeared = nil
                appeared?()
            }
            """)))
        XCTAssertTrue(receive.contains(collapsed("""
            didAppear: {
                (controller() as? WalletReceiveScreen)?.completeAppearance()
            },
            """)))

        let sheet = try collapsedSource("submodules/telegram-ios/submodules/Components/SheetComponent/Sources/SheetComponent.swift")
        XCTAssertTrue(sheet.contains(collapsed("""
            }, completion: { [weak self] completed in
                guard completed, let self, !self.isAnimatingOut else {
                    return
                }
                self.component?.didAppear()
            })
            """)))
    }

    func testWalletShowsTransactionsAfterReceiveAndCollectibleSendLikeSubmodule() throws {
        let controller = try collapsedSource("packages/WalletUI/Sources/WalletUI/WalletController.swift")
        for snippet in [
            """
            let showTransactions: () -> Void = {
                transferToReveal = nil
                revealsLatestTransactions = true
                if stateValue.with({ $0.selectedTab == .transactions }) {
                    revealLatestTransactionsImpl?()
                } else {
                    updateState { current in
                        var current = current
                        current.selectedTab = .transactions
                        return current
                    }
                }
            }
            """,
            """
            revealLatestTransactionsImpl = { [weak controller] in
                guard revealsLatestTransactions, let controller, stateValue.with({ $0.selectedTab == .transactions }) else {
                    return
                }
                revealsLatestTransactions = false
                let id = stateValue.with { $0.walletState.flatMap { walletVisibleTransactions($0.transactions.items).first?.presentationId } }
                if let id, let item = controller.tableView.item(stableId: InputDataEntryId.custom(walletHomeTransactionIdentifier(id))) {
                    controller.tableView.scroll(to: .top(id: item.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: -16), toVisible: true)
                } else {
                    controller.tableView.scroll(to: .up(false))
                }
            }
            """,
            """
            appeared: {
                guard walletContext.stateValue.walletAddress == address else {
                    return
                }
                showTransactions()
            }
            """,
            """
            current.suppressedCollectibleAddresses.insert(address)
                return current
            }
            showTransactions()
            """,
            """
            transferToReveal = id
            revealsLatestTransactions = false
            """,
            """
            transferToReveal = sent.presentationId
            revealsLatestTransactions = false
            """,
            """
            default:
                abandonRestoration()
                revealsLatestTransactions = false
            """,
            """
            revealLatestTransactionsImpl?()
            }
            """
        ] {
            XCTAssertTrue(controller.contains(collapsed(snippet)), snippet)
        }
        XCTAssertEqual(occurrences(of: "showTransactions()", in: controller), 2)

        let behavior = try collapsedSource("packages/WalletUI/Sources/WalletUI/WalletUIBehavior.swift")
        XCTAssertTrue(behavior.contains("return transactions.filter { $0.isVisibleInWalletHistory && $0.kind != .deployContract }"))

        let receive = try collapsedSource("packages/WalletUI/Sources/WalletUI/WalletReceiveController.swift")
        XCTAssertTrue(receive.contains(collapsed("""
            controller.didAppear = { _ in
                let completion = appeared
                appeared = nil
                completion?()
            }
            """)))

        let modal = try collapsedSource("packages/TGUIKit/Sources/Modal.swift")
        XCTAssertTrue(modal.contains(collapsed("""
            strongSelf.background.layer?.animateAlpha(from: 0, to: 1, duration: 0.15, completion:{[weak strongSelf] (completed) in
                strongSelf?.controller?.viewDidAppear(true)
            })
            """)))
    }
}
