import XCTest
import TelegramCore
@testable import QrStudioUI

final class QrStudioThemeTests: XCTestCase {
    private func theme(_ id: String, _ rgb: [UInt32]) -> QrStudioTheme {
        return QrStudioTheme(id: id, wallpaper: .color(rgb.first ?? 0), colors: rgb.map { QrStudioColor(rgb: $0) })
    }

    func testSelectingAThemeShowsIt() {
        var look = QrStudioLook()
        let classic = self.theme(QrStudioTheme.defaultId, [0xd6e4ef, 0x9fc2dd])
        look.themes = [classic]
        look.selectTheme(id: classic.id)
        XCTAssertEqual(look.kind, .color)
        XCTAssertEqual(look.backdrop, .theme(classic))
        XCTAssertEqual(look.settings.themeId, classic.id)
    }

    func testSelectingAPaletteClearsTheTheme() {
        var look = QrStudioLook()
        look.themes = [self.theme(QrStudioTheme.defaultId, [0xd6e4ef])]
        look.selectTheme(id: QrStudioTheme.defaultId)
        let palettes = (0 ..< 5).map { QrStudioPalette.profile(id: Int32($0), center: 0x6ec2b7 + UInt32($0), edge: 0x4891ad) }
        look.palettes = palettes
        look.selectPalette(id: .color(3))
        XCTAssertNil(look.themeId)
        XCTAssertEqual(look.backdrop, .color(palettes[3]))
    }

    func testUnknownThemeFallsBackToThePalette() {
        var look = QrStudioLook()
        look.themeId = "🦄"
        XCTAssertEqual(look.backdrop, .color(look.palette))
    }

    func testBrightWallpaperUsesLightGlassAndDarkInk() {
        let light = self.theme("a", [0xd6e4ef, 0xbcd7ea])
        XCTAssertTrue(light.isLight)
        XCTAssertLessThan(light.ink.luminance, 0.4)
        let dark = self.theme("b", [0x1c2b40, 0x0d1520])
        XCTAssertFalse(dark.isLight)
    }

    func testSettingsKeepTheThemeAndOldSettingsHaveNone() throws {
        var look = QrStudioLook()
        look.themes = [self.theme("🎄", [0xffffff])]
        look.selectTheme(id: "🎄")
        let data = try JSONEncoder().encode(look.settings)
        XCTAssertEqual(try JSONDecoder().decode(QrStudioLookSettings.self, from: data).themeId, "🎄")
        let old = QrStudioLookSettings(kind: 0, colorId: nil, emoji: [], giftId: nil)
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "themeId")
        let decoded = try JSONDecoder().decode(QrStudioLookSettings.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.themeId)
    }
}
