import XCTest
import Cocoa
@testable import WalletUI
@testable import SceneEffects

private struct SubmoduleInfoDiamond {
    let modes: Set<String>
    let height: CGFloat
    let viewOffset: CGFloat
    let layerOffset: CGFloat
    let usesBackgroundStarsLayer: Bool
    let hasPan: Bool
    let hasTap: Bool

    func layerFrame(availableWidth: CGFloat, logoSide: CGFloat) -> CGRect {
        let viewCenterY = logoSide / 2.0 + self.viewOffset
        let viewOriginY = viewCenterY - self.height / 2.0
        let layerCenterY = self.height * 0.5 - self.layerOffset
        return CGRect(x: 0.0, y: viewOriginY + layerCenterY - self.height / 2.0, width: availableWidth, height: self.height)
    }
}

final class WalletInfoSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func submoduleFile(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components").appendingPathComponent(path), encoding: .utf8)
    }

    private func match(_ pattern: String, in source: String) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let result = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)), pattern)
        return String(source[try XCTUnwrap(Range(result.range(at: 1), in: source))])
    }

    private func submoduleInfoDiamond() throws -> SubmoduleInfoDiamond {
        let screen = try submoduleFile("Wallet/WalletInfoScreen/Sources/WalletInfoScreen.swift")
        let modes = try match(#"if \[([^\]]+)\]\.contains\(component\.mode\) \{\s*let premiumDiamondSize"#, in: screen)
        let height = try match(#"let premiumDiamondSize = CGSize\(width: context\.availableSize\.width, height: ([0-9.]+)\)"#, in: screen)
        let viewOffset = try match(#"premiumDiamond\s*\.position\(CGPoint\(x: context\.availableSize\.width / 2\.0, y: contentSize\.height \+ animationSize\.height / 2\.0 \+ ([0-9.]+)\)\)"#, in: screen)

        let component = try submoduleFile("Premium/PremiumDiamondComponent/Sources/PremiumDiamondComponent.swift")
        let start = try XCTUnwrap(component.range(of: "public final class PremiumDiamondComponent"))
        let premium = String(component[start.lowerBound...])
        let layerOffset = try match(#"self\.diamondLayer\.position = CGPoint\(x: availableSize\.width \* 0\.5, y: availableSize\.height \* 0\.5 - ([0-9.]+)\)"#, in: premium)

        return SubmoduleInfoDiamond(
            modes: Set(modes.components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }),
            height: try XCTUnwrap(Double(height)).cgFloat,
            viewOffset: try XCTUnwrap(Double(viewOffset)).cgFloat,
            layerOffset: try XCTUnwrap(Double(layerOffset)).cgFloat,
            usesBackgroundStarsLayer: premium.contains("private let diamondLayer = InteractiveDiamondLayer()"),
            hasPan: premium.contains("UIPanGestureRecognizer(target: self.diamondLayer, action: #selector(InteractiveDiamondLayer.handlePan(_:)))"),
            hasTap: premium.contains("UITapGestureRecognizer(target: self.diamondLayer, action: #selector(InteractiveDiamondLayer.handleTap(_:)))")
        )
    }

    private func actualContent(_ mode: WalletInfoMode) -> WalletInfoContent {
        return walletInfoContent(mode: mode, fiatRateText: nil, gaslessDailyTransfers: 0)
    }

    func testLargeDiamondShowsInTheSubmoduleModes() throws {
        let submodule = try submoduleInfoDiamond()
        XCTAssertEqual(submodule.modes, ["wallet", "gram", "firstGrams"])
        let allModes: [WalletInfoMode] = [.wallet, .gram, .firstGrams, .recovery]
        let actualModes = Set(allModes.filter { actualContent($0).logo == .diamond }.map { String(describing: $0) })
        XCTAssertEqual(actualModes, submodule.modes)
    }

    #if arch(arm64)
    func testLargeDiamondSitsOnTheLogoCenterLikeTheSubmodule() throws {
        let submodule = try submoduleInfoDiamond()
        XCTAssertEqual(walletInfoDiamondHeight, submodule.height)
        for mode in [WalletInfoMode.wallet, .gram, .firstGrams] {
            let logoSize = actualContent(mode).logoSize
            for width in [CGFloat(320), 380, 452] {
                let actual = walletInfoDiamondFrame(rowWidth: width, logoSize: logoSize).offsetBy(dx: 0, dy: -10)
                let expected = submodule.layerFrame(availableWidth: width, logoSide: logoSize.height)
                XCTAssertEqual(actual, expected, "\(mode) at \(width)")
                XCTAssertEqual(actual.midY, logoSize.height / 2, accuracy: 0.001, "\(mode)")
            }
        }
    }

    func testLargeDiamondLayerMatchesTheSubmodulePremiumDiamond() throws {
        let submodule = try submoduleInfoDiamond()
        XCTAssertTrue(submodule.usesBackgroundStarsLayer)
        let view = WalletInfoDiamondView(frame: NSMakeRect(0, 0, 380, walletInfoDiamondHeight))
        XCTAssertEqual(view.diamondLayer.diamondStyle, InteractiveDiamondLayer().diamondStyle)
        XCTAssertTrue(view.diamondLayer.diamondStyle.backgroundStars)

        view.layout()
        XCTAssertEqual(view.diamondLayer.frame, view.bounds)

        view.update(lightBackground: true)
        XCTAssertTrue(view.diamondLayer.lightBackground)
        view.update(lightBackground: false)
        XCTAssertFalse(view.diamondLayer.lightBackground)

        let recognizers = view.gestureRecognizers
        let pan = recognizers.first(where: { $0 is NSPanGestureRecognizer })
        let click = recognizers.first(where: { $0 is NSClickGestureRecognizer })
        XCTAssertEqual(submodule.hasPan, pan != nil)
        XCTAssertEqual(submodule.hasTap, click != nil)
        XCTAssertTrue(pan?.target === view.diamondLayer)
        XCTAssertEqual(pan?.action, #selector(InteractiveDiamondLayer.handlePan(_:)))
        XCTAssertTrue(click?.target === view.diamondLayer)
        XCTAssertEqual(click?.action, #selector(InteractiveDiamondLayer.handleTap(_:)))
    }

    func testLargeDiamondRendersOnlyWhileOnScreen() {
        let view = WalletInfoDiamondView(frame: NSMakeRect(0, 0, 380, walletInfoDiamondHeight))
        XCTAssertFalse(view.diamondLayer.isInHierarchy)
        let window = NSWindow(contentRect: NSMakeRect(200, 200, 380, 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        XCTAssertTrue(view.diamondLayer.isInHierarchy)
        view.removeFromSuperview()
        XCTAssertFalse(view.diamondLayer.isInHierarchy)
    }
    #endif
}

private extension Double {
    var cgFloat: CGFloat {
        return CGFloat(self)
    }
}
