import XCTest
import Cocoa
@testable import WalletUI

private func repositoryRoot() -> URL {
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func source(_ path: String) throws -> String {
    return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
}

private func block(from start: String, to end: String, in source: String) throws -> String {
    let startRange = try XCTUnwrap(source.range(of: start), start)
    let endRange = try XCTUnwrap(source.range(of: end, range: startRange.upperBound ..< source.endIndex), end)
    return String(source[startRange.lowerBound ..< endRange.upperBound])
}

private func normalized(_ text: String) -> String {
    return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

final class WalletHomeBannerSubmoduleCompatibilityTests: XCTestCase {
    private let submoduleScreenPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletScreen/Sources/WalletScreen.swift"
    private let homePath = "packages/WalletUI/Sources/WalletUI/WalletController.swift"

    func testSubmoduleBannersFadeAndMoveTheCardWhileVisible() throws {
        let screen = try source(submoduleScreenPath)
        let transition = try block(from: "private var additionalBalancesTransition: ComponentTransition {", to: "return .immediate", in: screen)
        XCTAssertEqual(normalized(transition), "private var additionalBalancesTransition: ComponentTransition { if self.environment?.isVisible == true && self.window != nil { return .easeInOut(duration: 0.25) } return .immediate")
        XCTAssertEqual(screen.components(separatedBy: "self.componentState?.updated(transition: self.additionalBalancesTransition)").count - 1, 3)

        let section = try block(from: "let isVisible = !items.isEmpty", to: "return sectionSize.height + 10.0", in: screen)
        for line in [
            "transition.setAlpha(view: sectionView, alpha: 0.0, completion: { [weak self, weak sectionView] completed in",
            "self.additionalBalancesVisibilityGeneration == generation,",
            "!self.additionalBalancesIsVisible else {",
            "let sectionTransition: ComponentTransition = !wasVisible ? .immediate : transition",
            "transition.animateAlpha(view: sectionView, from: 0.0, to: 1.0)",
            "return 0.0"
        ] {
            XCTAssertTrue(section.contains(line), line)
        }

        let layout = try block(from: "let additionalBalancesOriginY = headerOriginY + headerSize.height + 10.0", to: "let cardOriginY = additionalBalancesOriginY + self.cardTransitionStart", in: screen)
        XCTAssertTrue(layout.contains("let contentLayoutTransition = compensateAdditionalBalancesOffset ? transition.withAnimation(.none) : transition"))
        XCTAssertTrue(screen.contains("self.updateScrolling(transition: contentLayoutTransition)"))
    }

    func testBannersAnimateEveryChangeLikeSubmodule() throws {
        let home = try source(homePath)
        XCTAssertTrue(home.contains("return InputDataSignalValue(entries: entries(state, arguments: arguments), animated: true)"))
        for refresh in ["current.existingWaltBalance = balance", "current.availableEarnings = availableBalance.amount.value", "current.previousWalletsBalance = balance"] {
            XCTAssertTrue(home.contains(refresh), refresh)
        }
    }

    func testBannersNeverRenumberTheCardAndTheRowsBelow() throws {
        let home = try source(homePath)
        let banners = normalized(try block(from: "for banner in banners {", to: "identifier: _id_card,", in: home))
        let parts = banners.components(separatedBy: "if !banners.isEmpty { entries.append(.sectionId(sectionId, type: .customModern(10))) } sectionId += 1 index = 0 ")
        XCTAssertEqual(parts.count, 2, banners)
        XCTAssertFalse(parts.last?.contains("sectionId +=") ?? true)
        XCTAssertFalse(parts.last?.contains("index +=") ?? true)
        XCTAssertTrue(parts.last?.hasSuffix("entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_card,") ?? false)
    }
}
