import XCTest
import Cocoa
@testable import WalletUI

private struct SubmoduleCardBalance {
    let balanceRightEdge: CGFloat
    let balanceScale: CGFloat
    let secondaryScale: CGFloat
    let currencyMaxX: CGFloat
    let secondaryMaxX: CGFloat

    init(width: CGFloat, scale: CGFloat, iconSize: CGSize, fractionalText: String, unscaledIntegralTextSize: CGSize, unscaledFractionalSize: CGSize, unscaledCurrencySize: CGSize, unscaledSecondarySize: CGSize) {
        let qrSize = CGSize(width: max(iconSize.width, 50.0), height: max(iconSize.height, 38.0))
        let qrFrame = CGRect(
            origin: CGPoint(x: width - qrSize.width - 47.0 * scale, y: 82.0 * scale),
            size: qrSize
        )
        let balanceRightEdge = qrFrame.minX - 10.0 * scale
        let balanceOriginX = 20.0 * scale
        let unscaledBalanceWidth = (33.25 + (fractionalText.isEmpty ? 0.0 : 1.0) + 5.0) * scale
            + unscaledIntegralTextSize.width + unscaledFractionalSize.width + unscaledCurrencySize.width
        let balanceScale = min(1.0, max(0.0, balanceRightEdge - balanceOriginX) / max(1.0, unscaledBalanceWidth))
        let balanceContentScale = scale * balanceScale
        let integralTextSize = CGSize(width: unscaledIntegralTextSize.width * balanceScale, height: unscaledIntegralTextSize.height * balanceScale)
        let fractionalSize = CGSize(width: unscaledFractionalSize.width * balanceScale, height: unscaledFractionalSize.height * balanceScale)
        let currencySize = CGSize(width: unscaledCurrencySize.width * balanceScale, height: unscaledCurrencySize.height * balanceScale)
        let gramIconSize = CGSize(width: 30.0 * balanceContentScale, height: 30.0 * balanceContentScale)
        let gramIconSpacing = gramIconSize.width + 3.25 * balanceContentScale
        var mainOriginX = balanceOriginX
        mainOriginX += gramIconSpacing + integralTextSize.width
        if !fractionalText.isEmpty {
            mainOriginX += 1.0 * balanceContentScale
        }
        mainOriginX += fractionalSize.width
        mainOriginX += 5.0 * balanceContentScale
        let secondaryScale = min(1.0, max(0.0, balanceRightEdge - 24.0 * scale) / max(1.0, unscaledSecondarySize.width))

        self.balanceRightEdge = balanceRightEdge
        self.balanceScale = balanceScale
        self.secondaryScale = secondaryScale
        self.currencyMaxX = mainOriginX + currencySize.width
        self.secondaryMaxX = 24.0 * scale + unscaledSecondarySize.width * secondaryScale
    }
}

final class WalletCardBalanceFitSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    func testSubmoduleCardStillFitsTheBalanceWithTheCopiedRules() throws {
        let card = try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardComponent.swift")
        for line in [
            "minSize: CGSize(width: 50.0, height: 38.0),",
            "origin: CGPoint(x: width - qrSize.width - 47.0 * scale, y: 82.0 * scale),",
            "let balanceRightEdge = qrFrame.minX - 10.0 * scale",
            "let balanceOriginX = 20.0 * scale",
            "let unscaledBalanceWidth = (33.25 + (fractionalText.isEmpty ? 0.0 : 1.0) + 5.0) * scale",
            "+ unscaledIntegralTextSize.width + unscaledFractionalSize.width + unscaledCurrencySize.width",
            "let balanceScale = min(1.0, max(0.0, balanceRightEdge - balanceOriginX) / max(1.0, unscaledBalanceWidth))",
            "let balanceContentScale = scale * balanceScale",
            "mainOriginX += 1.0 * balanceContentScale",
            "mainOriginX += 5.0 * balanceContentScale",
            "let secondaryScale = min(1.0, max(0.0, balanceRightEdge - 24.0 * scale) / max(1.0, unscaledSecondarySize.width))",
            "origin: CGPoint(x: 24.0 * scale, y: 114.0 * scale),",
            "transition.setScale(view: integralView, scale: balanceScale)",
            "transition.setScale(view: fractionalView, scale: balanceScale)",
            "transition.setScale(view: currencyView, scale: balanceScale)",
            "transition.setScale(view: secondaryView, scale: secondaryScale)",
            "let mainBaselineY = integralOriginY + floorToScreenPixels(integralFont.ascender) * balanceScale",
            "context.scaleBy(x: self.primaryBalanceScale, y: self.primaryBalanceScale)"
        ] {
            XCTAssertTrue(card.contains(line), line)
        }

        let button = try source("submodules/telegram-ios/submodules/TelegramUI/Components/PlainButtonComponent/Sources/PlainButtonComponent.swift")
        XCTAssertTrue(button.contains("size.width = max(size.width, minSize.width)"))
        XCTAssertTrue(button.contains("size.height = max(size.height, minSize.height)"))
    }

    func testCardMeasuresTheFitAgainstTheSubmoduleQrButton() throws {
        let card = try source("packages/WalletUI/Sources/WalletUI/WalletCardView.swift")
        for line in [
            "return NSMakeSize(max(50.0, iconSize.width), max(38.0, iconSize.height))",
            "qrWidth: qrButtonSize(scale: scale).width,",
            "qrButton.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, width - qrButtonSize.width - 47.0 * scale), floorToScreenPixels(backingScaleFactor, 82.0 * scale), qrButtonSize.width, qrButtonSize.height)",
            "let qrChipFrame = qrButton.bounds.focus(self.qrIconSize(scale: scale))",
            "balanceScale = fit.balanceScale",
            "fiatScale = fit.fiatScale",
            "view.layer?.transform = CATransform3DScale(CATransform3DMakeTranslation(parallaxX * 4, parallaxY * 4, 0), balanceScale, balanceScale, 1.0)",
            "fiatView.layer?.transform = CATransform3DScale(CATransform3DMakeTranslation(parallaxX * 3.5, parallaxY * 3.5, 0), fiatScale, fiatScale, 1.0)",
            "let integralHeight = integralView.frame.height * balanceScale",
            "let mainBaselineY = integralY + walletCardTextBaseline(integralView) * balanceScale",
            "mainOriginX += integralView.frame.width * balanceScale",
            "mainOriginX += fractionalView.frame.width * balanceScale",
            "currencyView.setFrameOrigin(NSMakePoint(mainOriginX, mainBaselineY - walletCardTextBaseline(currencyView) * balanceScale))",
            "ctx.scaleBy(x: self.balanceScale, y: self.balanceScale)",
            "let layout = WalletCardDiamondLayout(scale: scale, balanceScale: balanceScale)",
            "let diamondLayout = WalletCardDiamondLayout(scale: scale, balanceScale: balanceScale)",
            "mainOriginX += 1.0 * scale * balanceScale",
            "mainOriginX += 5.0 * scale * balanceScale"
        ] {
            XCTAssertTrue(card.contains(line), line)
        }
    }

    func testBalanceFitMatchesSubmodule() {
        for width: CGFloat in [300.0, 336.0, 370.0, 420.0] {
            let scale = width / 370.0
            let iconSize = CGSize(width: floor(50.0 * scale), height: floor(38.0 * scale))
            for hasFractional in [false, true] {
                for textWidth: CGFloat in [40.0, 120.0, 180.0, 260.0, 420.0] {
                    for fiatWidth: CGFloat in [30.0, 160.0, 240.0, 400.0] {
                        let integral = CGSize(width: textWidth * 0.6, height: 26.0)
                        let fractional = CGSize(width: hasFractional ? textWidth * 0.15 : 0.0, height: 21.0)
                        let currency = CGSize(width: textWidth * 0.25, height: 26.0)
                        let submodule = SubmoduleCardBalance(width: width, scale: scale, iconSize: iconSize, fractionalText: hasFractional ? ".5" : "", unscaledIntegralTextSize: integral, unscaledFractionalSize: fractional, unscaledCurrencySize: currency, unscaledSecondarySize: CGSize(width: fiatWidth, height: 17.0))
                        let actual = WalletCardBalanceFit(width: width, scale: scale, qrWidth: max(50.0, iconSize.width), hasFractional: hasFractional, balanceTextWidth: integral.width + fractional.width + currency.width, fiatWidth: fiatWidth)
                        let label = "width \(width) fractional \(hasFractional) text \(textWidth) fiat \(fiatWidth)"
                        XCTAssertEqual(actual.balanceScale, submodule.balanceScale, accuracy: 1e-9, label)
                        XCTAssertEqual(actual.fiatScale, submodule.secondaryScale, accuracy: 1e-9, label)
                        if submodule.balanceScale > 0.0 && submodule.balanceScale < 1.0 {
                            XCTAssertEqual(submodule.currencyMaxX, submodule.balanceRightEdge, accuracy: 1e-9, label)
                        }
                    }
                }
            }
        }
    }

    func testShortBalanceKeepsItsFullSizeLikeSubmodule() {
        let fit = WalletCardBalanceFit(width: 336.0, scale: 336.0 / 370.0, qrWidth: 50.0, hasFractional: true, balanceTextWidth: 90.0, fiatWidth: 60.0)
        XCTAssertEqual(fit.balanceScale, 1.0)
        XCTAssertEqual(fit.fiatScale, 1.0)
    }
}
