import XCTest
import SwiftSignalKit
@testable import GiftControls

final class WalletPreloadTests: XCTestCase {
    private func gift(_ id: String) -> WalletContext.Collectible {
        .init(address: id, giftSlug: id)
    }

    func testWarmCacheReusedWhenOpeningWallet() {
        let context = TestAccount()
        let cache = WalletCollectibleArtworks()
        let collectible = gift("warm")
        cache.preload(collectible, context: context, modelFile: Data([1]))
        var value: WalletCollectibleArtwork?
        let subscription = cache.artwork(collectible, context: context, modelFile: Data([1])).start(next: { value = $0 })
        defer { subscription.dispose() }
        XCTAssertEqual(context.engine.payments.requests, ["warm"])
        XCTAssertNotNil(value?.gift)
        XCTAssertEqual(value?.modelFile, Data([1]))
        XCTAssertEqual(value?.art, true)
    }

    func testFailedPreloadCanRetryOnOpen() {
        let context = TestAccount()
        let cache = WalletCollectibleArtworks()
        context.engine.payments.fail = true
        cache.preload(gift("retry"), context: context, modelFile: nil)
        context.engine.payments.fail = false
        let subscription = cache.artwork(gift("retry"), context: context).start()
        defer { subscription.dispose() }
        XCTAssertEqual(context.engine.payments.requests, ["retry", "retry"])
        XCTAssertNotNil(cache.current("retry").gift)
    }

    func testConcurrentOpenSharesInflightRequest() {
        let context = TestAccount()
        context.engine.payments.response = .never()
        let cache = WalletCollectibleArtworks()
        cache.preload(gift("pending"), context: context, modelFile: nil)
        let subscription = cache.artwork(gift("pending"), context: context).start()
        subscription.dispose()
        XCTAssertEqual(context.engine.payments.requests, ["pending"])
    }

    func testEmbeddedGiftNeedsNoMetadataRequest() {
        let context = TestAccount()
        let cache = WalletCollectibleArtworks()
        var collectible = gift("embedded")
        collectible.nft = .init(gift: .init(id: 42))
        cache.preload(collectible, context: context, modelFile: nil)
        XCTAssertTrue(context.engine.payments.requests.isEmpty)
        XCTAssertEqual(cache.current("embedded").gift?.id, 42)
    }

    func testCardPreloadBoundedDeduplicatedAndBuildGated() {
        let context = TestAccount()
        let prefix = UUID().uuidString
        let stickers = (0..<15).map { WalletCard.Sticker(gift: gift("\(prefix)-\($0)")) }
        preloadWalletPeerCard(context: context, card: .init(stickers: stickers))
        preloadWalletPeerCard(context: context, card: .init(stickers: stickers))
        #if DEBUG && !BETA
        XCTAssertEqual(context.engine.payments.requests.count, 10)
        #else
        XCTAssertTrue(context.engine.payments.requests.isEmpty)
        #endif
    }

    func testInvalidAndDuplicateStickersAreSkipped() {
        let context = TestAccount()
        let collectible = gift(UUID().uuidString)
        let card = WalletCard(stickers: [.init(gift: gift("invalid"), valid: false), .init(gift: collectible), .init(gift: collectible)])
        preloadWalletPeerCard(context: context, card: card)
        #if DEBUG && !BETA
        XCTAssertEqual(context.engine.payments.requests, [collectible.address])
        #else
        XCTAssertTrue(context.engine.payments.requests.isEmpty)
        #endif
    }
}
