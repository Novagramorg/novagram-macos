import XCTest
@testable import WalletEngineFFI

final class WalletEngineFFITests: XCTestCase {
    func testMnemonicWordlist() {
        let words = mnemonicWordlist()
        XCTAssertEqual(words.count, 2048)
        XCTAssertEqual(words.first, "abandon")
    }

    func testAddressValidation() throws {
        XCTAssertFalse(isValidTonAddress(value: "not an address"))
        let raw = "0:83dfd552e63929b7c2d8fa2eebc42dd8e05ba38b7477a10b7c2d8fa2eebc42dd"
        XCTAssertTrue(isValidTonAddress(value: raw))
        let friendly = try convertTonAddress(value: raw, format: .userFriendly(bounceable: false, testnet: false))
        XCTAssertTrue(isValidTonAddress(value: friendly))
        XCTAssertEqual(try convertTonAddress(value: friendly, format: .raw), raw)
    }

    func testDetectMnemonicSchemes() {
        let bip39Twelve = ["abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"]
        XCTAssertFalse(detectMnemonicSchemes(words: bip39Twelve).isEmpty)
    }
}
