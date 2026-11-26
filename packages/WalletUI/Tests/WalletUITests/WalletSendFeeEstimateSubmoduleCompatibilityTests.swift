import XCTest
import WalletContext
import TelegramCore
import Postbox
@testable import WalletUI

private struct SubmoduleSendFeeRequest: Equatable {
    let walletAddress: String
    let walletPublicKey: String
    let address: String
    let comment: WalletContext.TransferFeeComment
}

private func submoduleCommentEncrypted(hasPeer: Bool, comment: String?, isCommentPublic: Bool) -> Bool {
    return hasPeer
        && comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        && !isCommentPublic
}

private func submoduleCurrentFeeRequest(walletInfo: WalletContext.WalletInfo?, recipientAddress: String, comment: String?, commentEncrypted: Bool) -> SubmoduleSendFeeRequest? {
    guard let walletInfo, !recipientAddress.isEmpty else { return nil }
    let feeComment: WalletContext.TransferFeeComment
    if commentEncrypted {
        feeComment = .encrypted
    } else if let text = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
        feeComment = .plainText(byteCount: text.utf8.count)
    } else {
        feeComment = .none
    }
    return SubmoduleSendFeeRequest(
        walletAddress: walletInfo.address,
        walletPublicKey: walletInfo.publicKey,
        address: recipientAddress,
        comment: feeComment
    )
}

private func submodulePeerTransferEstimatedFee(currentFeeRequest: SubmoduleSendFeeRequest?, feeRequest: SubmoduleSendFeeRequest?, requestFeeRequest: SubmoduleSendFeeRequest?, cachedFee: Int64?) -> Int64?? {
    guard currentFeeRequest == requestFeeRequest,
          feeRequest == requestFeeRequest, cachedFee != nil else { return nil }
    return .some(cachedFee)
}

private enum SubmodulePendingPeerSend: Equatable {
    case wait
    case send(estimatedFee: Int64?)
    case cancel
    case fail(WalletContext.WalletError)
}

private func submodulePendingPeerSend(currentFeeRequest: SubmoduleSendFeeRequest?, pendingFeeRequest: SubmoduleSendFeeRequest, feeRequest: SubmoduleSendFeeRequest?, cachedFee: Int64?, estimateError: WalletContext.WalletError?) -> SubmodulePendingPeerSend {
    guard currentFeeRequest == pendingFeeRequest else {
        return .cancel
    }
    if feeRequest == pendingFeeRequest, let estimateError {
        return .fail(estimateError)
    }
    guard currentFeeRequest == pendingFeeRequest,
          feeRequest == pendingFeeRequest, cachedFee != nil else { return .wait }
    return .send(estimatedFee: cachedFee)
}

@available(macOS 10.15, *)
private func actualPendingPeerSend(_ readiness: WalletSendFeeReadiness) -> SubmodulePendingPeerSend {
    switch readiness {
    case .estimating:
        return .wait
    case let .ready(fee):
        return .send(estimatedFee: fee)
    case .changed:
        return .cancel
    case let .failed(error):
        return .fail(error)
    }
}

private func submoduleOpenPreviewInitialFee(feeRequest: SubmoduleSendFeeRequest?, requestFeeRequest: SubmoduleSendFeeRequest?, cachedFee: Int64?) -> Int64? {
    return feeRequest == requestFeeRequest ? cachedFee : nil
}

private func submoduleTransactionComment(_ value: String?) -> String? {
    guard var value else {
        return nil
    }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func submodulePreviewEstimatedFee(sendAll: Bool, hasPreparedTransfer: Bool, sourceHasPreparedTransfer: Bool, preparedTransferNeedsRefresh: Bool, previewAge: TimeInterval, comment: String?, sourceComment: String?, previewCommentEncrypted: Bool, sourceCommentEncrypted: Bool, initialFee: Int64?) -> Int64? {
    let estimatedFee: Int64?
    if !sendAll, !hasPreparedTransfer, !sourceHasPreparedTransfer,
       !preparedTransferNeedsRefresh, previewAge >= 0, previewAge < 300,
       comment == submoduleTransactionComment(sourceComment),
       previewCommentEncrypted == sourceCommentEncrypted {
        estimatedFee = initialFee
    } else {
        estimatedFee = nil
    }
    return estimatedFee
}

private func submoduleEstimatorFee(_ comment: WalletContext.TransferFeeComment) -> Int64 {
    switch comment {
    case .none:
        return 3_100_000
    case let .plainText(byteCount):
        return 3_100_000 + Int64(byteCount) * 2_000
    case .encrypted:
        return 6_400_000
    }
}

@available(macOS 10.15, *)
private func actualFeeRequest(_ request: WalletSendFeeRequest?) -> SubmoduleSendFeeRequest? {
    return request.map { SubmoduleSendFeeRequest(walletAddress: $0.walletAddress, walletPublicKey: $0.walletPublicKey, address: $0.address, comment: $0.comment) }
}

final class WalletSendFeeEstimateSubmoduleCompatibilityTests: XCTestCase {
    private let walletAddress = "0:" + String(repeating: "1", count: 64)
    private let otherAddress = "0:" + String(repeating: "2", count: 64)
    private let comments: [String?] = [nil, "", "  \n", "Dinner", "  Dinner \n", "Привет 👋"]

    private func walletInfo() -> WalletContext.WalletInfo {
        return WalletContext.WalletInfo(address: walletAddress, publicKey: "key")
    }

    private func recipientPeer() -> EnginePeer {
        return .legacyGroup(TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(1)), title: "Alice", photo: [], participantCount: 1, role: .creator(rank: nil), membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0))
    }

    private func sendState(hasPeer: Bool, amount: Int64, comment: String?, isCommentPublic: Bool) -> WalletSendState {
        var state = WalletSendState()
        state.amount = amount
        state.balance = 10_000_000_000
        state.isLoading = false
        state.gaslessInfo = WalletGaslessInfo(available: true, left: 5, resetAt: 0, minAmount: 1_000_000_000, relayerAddress: otherAddress)
        state.gaslessMinAmount = 1_000_000_000
        state.walletPhase = .wallet(walletInfo())
        state.walletAddress = walletInfo().address
        state.selectedPeer = hasPeer ? recipientPeer() : nil
        state.resolved = .init(address: otherAddress, displayName: nil)
        state.comment = comment
        state.isCommentPublic = isCommentPublic
        return state
    }

    func testFeeRequestMatchesSubmodule() {
        for hasPeer in [false, true] {
            for comment in comments {
                for isCommentPublic in [false, true] {
                    for hasWallet in [false, true] {
                        for hasRecipient in [false, true] {
                            var state = sendState(hasPeer: hasPeer, amount: 500_000_000, comment: comment, isCommentPublic: isCommentPublic)
                            if !hasWallet {
                                state.walletPhase = nil
                                state.walletAddress = nil
                            }
                            if !hasRecipient {
                                state.resolved = nil
                            }
                            let submodule = submoduleCurrentFeeRequest(
                                walletInfo: hasWallet ? walletInfo() : nil,
                                recipientAddress: hasRecipient ? otherAddress : "",
                                comment: comment,
                                commentEncrypted: submoduleCommentEncrypted(hasPeer: hasPeer, comment: comment, isCommentPublic: isCommentPublic)
                            )
                            XCTAssertEqual(actualFeeRequest(walletSendFeeRequest(state)), submodule, "peer \(hasPeer) comment \(String(describing: comment)) public \(isCommentPublic) wallet \(hasWallet) recipient \(hasRecipient)")
                        }
                    }
                }
            }
        }
    }

    func testFeeRequestIgnoresAmountLikeSubmodule() {
        let base = walletSendFeeRequest(sendState(hasPeer: true, amount: 500_000_000, comment: "Dinner", isCommentPublic: false))
        XCTAssertNotNil(base)
        for amount: Int64 in [1, 500_000_000, 2_000_000_000, 10_000_000_000, 20_000_000_000] {
            XCTAssertEqual(walletSendFeeRequest(sendState(hasPeer: true, amount: amount, comment: "Dinner", isCommentPublic: false)), base, "amount \(amount)")
        }
        XCTAssertEqual(base?.comment, .encrypted)
        XCTAssertEqual(walletSendFeeRequest(sendState(hasPeer: true, amount: 500_000_000, comment: "A much longer dinner note", isCommentPublic: false)), base)
    }

    func testPeerTransferEstimatedFeeMatchesSubmodule() {
        for amount: Int64 in [500_000_000, 2_000_000_000, 10_000_000_000] {
            for comment in comments {
                for isCommentPublic in [false, true] {
                    var state = sendState(hasPeer: true, amount: amount, comment: comment, isCommentPublic: isCommentPublic)
                    let submoduleRequest = submoduleCurrentFeeRequest(walletInfo: walletInfo(), recipientAddress: otherAddress, comment: comment, commentEncrypted: submoduleCommentEncrypted(hasPeer: true, comment: comment, isCommentPublic: isCommentPublic))
                    let submoduleCachedFee = submoduleRequest.map { submoduleEstimatorFee($0.comment) }
                    let submodule = submodulePeerTransferEstimatedFee(currentFeeRequest: submoduleRequest, feeRequest: submoduleRequest, requestFeeRequest: submoduleRequest, cachedFee: submoduleCachedFee)

                    let request = walletSendFeeRequest(state)!
                    state.feeEstimate = WalletSendFeeEstimate(request: request, fee: submoduleEstimatorFee(request.comment))
                    let label = "amount \(amount) comment \(String(describing: comment)) public \(isCommentPublic)"
                    XCTAssertNotNil(submodule, label)
                    XCTAssertEqual(walletSendInitialFee(state), submodule ?? nil, label)
                }
            }
        }
    }

    func testPeerTransferDropsEstimateForAnotherCommentKind() {
        var state = sendState(hasPeer: true, amount: 500_000_000, comment: nil, isCommentPublic: false)
        let plainRequest = walletSendFeeRequest(state)!
        state.feeEstimate = WalletSendFeeEstimate(request: plainRequest, fee: submoduleEstimatorFee(plainRequest.comment))
        state.comment = "Secret dinner money"
        let encryptedRequest = submoduleCurrentFeeRequest(walletInfo: walletInfo(), recipientAddress: otherAddress, comment: state.comment, commentEncrypted: true)
        let submoduleStale = submodulePeerTransferEstimatedFee(currentFeeRequest: encryptedRequest, feeRequest: actualFeeRequest(plainRequest), requestFeeRequest: encryptedRequest, cachedFee: submoduleEstimatorFee(plainRequest.comment))
        XCTAssertNil(submoduleStale)
        XCTAssertNil(walletSendInitialFee(state))

        let request = walletSendFeeRequest(state)!
        XCTAssertEqual(actualFeeRequest(request), encryptedRequest)
        state.feeEstimate = WalletSendFeeEstimate(request: request, fee: submoduleEstimatorFee(request.comment))
        XCTAssertEqual(walletSendInitialFee(state), 6_400_000)
        state.feeEstimate = WalletSendFeeEstimate(request: request, fee: nil)
        XCTAssertNil(walletSendInitialFee(state))
    }

    func testPeerSendWaitsForFeeEstimateLikeSubmodule() {
        let pressed = sendState(hasPeer: true, amount: 500_000_000, comment: "Dinner", isCommentPublic: false)
        let pendingRequest = walletSendFeeRequest(pressed)!
        let otherRequest = walletSendFeeRequest(sendState(hasPeer: true, amount: 500_000_000, comment: nil, isCommentPublic: false))!
        let submodulePending = actualFeeRequest(pendingRequest)!
        struct Scenario {
            let comment: String?
            let estimate: WalletSendFeeEstimate?
        }
        let scenarios = [
            Scenario(comment: "Dinner", estimate: nil),
            Scenario(comment: "Dinner", estimate: WalletSendFeeEstimate(request: otherRequest, fee: 3_100_000)),
            Scenario(comment: "Dinner", estimate: WalletSendFeeEstimate(request: pendingRequest, fee: 6_400_000)),
            Scenario(comment: "Dinner", estimate: WalletSendFeeEstimate(request: pendingRequest, fee: nil, error: .network)),
            Scenario(comment: "Dinner", estimate: WalletSendFeeEstimate(request: pendingRequest, fee: nil, error: .previewIncomplete)),
            Scenario(comment: nil, estimate: WalletSendFeeEstimate(request: pendingRequest, fee: 6_400_000)),
            Scenario(comment: nil, estimate: nil),
        ]
        for scenario in scenarios {
            var state = sendState(hasPeer: true, amount: 500_000_000, comment: scenario.comment, isCommentPublic: false)
            state.isSending = true
            state.feeEstimate = scenario.estimate
            let current = actualFeeRequest(walletSendFeeRequest(state))
            let submodule = submodulePendingPeerSend(
                currentFeeRequest: current,
                pendingFeeRequest: submodulePending,
                feeRequest: actualFeeRequest(scenario.estimate?.request),
                cachedFee: scenario.estimate?.fee,
                estimateError: scenario.estimate?.error
            )
            XCTAssertEqual(actualPendingPeerSend(walletSendFeeReadiness(state, request: pendingRequest)), submodule, "comment \(String(describing: scenario.comment)) estimate \(String(describing: scenario.estimate))")
        }
    }

    func testConfirmationEstimatedFeeMatchesSubmodule() {
        let sourceComments: [String?] = [nil, "Dinner", "  Dinner "]
        let previewComments: [String?] = [nil, "Dinner", "Lunch"]
        for initialFee: Int64? in [nil, 0, 3_100_000] {
            for sourceComment in sourceComments {
                for comment in previewComments {
                    for sendAll in [false, true] {
                        for hasPreparedTransfer in [false, true] {
                            for needsRefresh in [false, true] {
                                for previewAge: TimeInterval in [-1, 0, 120, 299.9, 300, 600] {
                                    for encryptComment in [false, true] {
                                        let subject = WalletTransactionSubject.preview(address: otherAddress, amount: 500_000_000, sendAll: sendAll, comment: sourceComment, initialFee: initialFee)
                                        let actual = walletPreviewEstimatedFee(subject: subject, sendAll: sendAll, hasPreparedTransfer: hasPreparedTransfer, needsRefresh: needsRefresh, previewAge: previewAge, comment: comment, encryptComment: encryptComment)
                                        let submodule = submodulePreviewEstimatedFee(sendAll: sendAll, hasPreparedTransfer: hasPreparedTransfer, sourceHasPreparedTransfer: false, preparedTransferNeedsRefresh: needsRefresh, previewAge: previewAge, comment: comment, sourceComment: sourceComment, previewCommentEncrypted: encryptComment, sourceCommentEncrypted: false, initialFee: initialFee)
                                        XCTAssertEqual(actual, submodule, "fee \(String(describing: initialFee)) source \(String(describing: sourceComment)) comment \(String(describing: comment)) all \(sendAll) prepared \(hasPreparedTransfer) refresh \(needsRefresh) age \(previewAge) encrypt \(encryptComment)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testConfirmationSkipsEstimateForCollectibles() {
        let collectible = WalletContext.Collectible(address: "nft", name: "Gift", kind: .gift, nft: WalletNftItem(collectionAddress: nil, address: "nft", ownerAddress: walletAddress, index: "1", name: "Gift", description: nil, image: nil, imageSmall: nil, contentUrl: nil, lottie: nil, attributes: nil, extra: nil))
        XCTAssertNil(walletPreviewEstimatedFee(subject: .collectiblePreview(address: otherAddress, collectible: collectible), sendAll: false, hasPreparedTransfer: false, needsRefresh: false, previewAge: 0, comment: nil, encryptComment: false))
    }

    func testSendToConfirmationEstimatedFeeMatchesSubmodule() {
        for amount: Int64 in [500_000_000, 2_000_000_000, 10_000_000_000] {
            for comment in comments {
                var state = sendState(hasPeer: false, amount: amount, comment: comment, isCommentPublic: false)
                let request = walletSendFeeRequest(state)!
                state.feeEstimate = WalletSendFeeEstimate(request: request, fee: submoduleEstimatorFee(request.comment))
                let sendAll = walletShouldSendAll(state)
                let subject = WalletTransactionSubject.preview(address: otherAddress, amount: amount, sendAll: sendAll, comment: state.comment, initialFee: walletSendInitialFee(state))
                let actual = walletPreviewEstimatedFee(subject: subject, sendAll: sendAll, hasPreparedTransfer: false, needsRefresh: false, previewAge: 0, comment: walletTransactionComment(state.comment), encryptComment: false)

                let submoduleRequest = submoduleCurrentFeeRequest(walletInfo: walletInfo(), recipientAddress: otherAddress, comment: comment, commentEncrypted: false)
                let submoduleInitialFee = submoduleOpenPreviewInitialFee(feeRequest: submoduleRequest, requestFeeRequest: submoduleRequest, cachedFee: submoduleRequest.map { submoduleEstimatorFee($0.comment) })
                let submodule = submodulePreviewEstimatedFee(sendAll: sendAll, hasPreparedTransfer: false, sourceHasPreparedTransfer: false, preparedTransferNeedsRefresh: false, previewAge: 0, comment: submoduleTransactionComment(comment), sourceComment: comment, previewCommentEncrypted: false, sourceCommentEncrypted: false, initialFee: submoduleInitialFee)

                let label = "amount \(amount) comment \(String(describing: comment))"
                XCTAssertEqual(actual, submodule, label)
                XCTAssertEqual(actual, sendAll ? nil : submoduleInitialFee, label)
            }
        }
    }
}
