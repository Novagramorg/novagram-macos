import Cocoa
import SwiftSignalKit

struct WalletCollectibleArtwork {
    var gift: StarGift.UniqueGift?
    var art: Bool?
    var modelFile: Data?
}
struct StarGift {
    struct UniqueGift { let id: Int }
}
typealias MediaId = Int
struct TelegramMediaFile { let fileId: Int }
struct Postbox {}
func walletDecodedMediaFile(_ data: Data) -> TelegramMediaFile? { data.first.map { TelegramMediaFile(fileId: Int($0)) } }
struct WalletContext {
    struct Collectible {
        enum Kind { case gift, other }
        struct NFT { let gift: StarGift.UniqueGift? }
        let address: String
        var kind: Kind = .gift
        var nft: NFT?
        var giftSlug: String?
    }
    struct CardSticker {
        let gift: Collectible
        let modelFile: Data?
        init?(serverSticker: WalletCard.Sticker, backgroundNftAddress: String?) {
            guard serverSticker.valid else { return nil }
            gift = serverSticker.gift
            modelFile = serverSticker.modelFile
        }
    }
}
struct WalletCard {
    struct Sticker {
        let gift: WalletContext.Collectible
        var modelFile: Data?
        var valid = true
    }
    var stickers: [Sticker]
    var backgroundNft: WalletContext.Collectible?
}
protocol AccountContextProtocol {
    var account: Account { get }
    var engine: Engine { get }
}
struct Account { let postbox = Postbox() }
struct Engine { let payments: Payments }
final class Payments {
    enum Failure: Error { case offline }
    var requests: [String] = []
    var fail = false
    var response: Signal<StarGift.UniqueGift, Failure>?
    func getUniqueStarGift(slug: String) -> Signal<StarGift.UniqueGift, Failure> {
        requests.append(slug)
        return response ?? (fail ? .fail(.offline) : .single(.init(id: requests.count)))
    }
}
final class TestAccount: AccountContextProtocol {
    let account = Account()
    let engine = Engine(payments: Payments())
}
