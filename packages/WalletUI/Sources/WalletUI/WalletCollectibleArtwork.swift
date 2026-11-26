import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import WalletContext

struct WalletCollectibleArtwork {
    var gift: StarGift.UniqueGift?
    var art: CGImage?
    var modelFile: Data?
    var styleSource: (inner: Int32, outer: Int32, pattern: Int32, patternFile: Data?)?
    var pattern: CGImage?
}

private func walletCollectibleModelFile(_ gift: StarGift.UniqueGift) -> TelegramMediaFile? {
    for attribute in gift.attributes {
        if case let .model(_, file, _, _) = attribute {
            return file
        }
    }
    return nil
}

private func walletCollectibleFileReference(_ file: TelegramMediaFile) -> FileMediaReference {
    for attribute in file.attributes {
        switch attribute {
        case let .Sticker(_, packReference, _):
            if let packReference {
                return .stickerPack(stickerPack: packReference, media: file)
            }
        case let .CustomEmoji(_, _, _, packReference):
            if let packReference {
                return .stickerPack(stickerPack: packReference, media: file)
            }
        default:
            break
        }
    }
    return .standalone(media: file)
}

private func walletCollectibleCanvas(_ image: CGImage, side: Int, inset: CGFloat) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    let box = CGFloat(side) * (1 - inset * 2)
    let fit = min(box / CGFloat(image.width), box / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2, width: size.width, height: size.height))
    return context.makeImage()
}

func walletEncodedMediaFile(_ file: TelegramMediaFile) -> Data {
    let encoder = PostboxEncoder()
    encoder.encodeRootObject(file)
    return encoder.makeData()
}

func walletDecodedMediaFile(_ data: Data) -> TelegramMediaFile? {
    return PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? TelegramMediaFile
}

final class WalletCollectibleArtworks {
    static let shared = WalletCollectibleArtworks()
    static let artSide: Int = 320
    static let artInset: CGFloat = 0.035
    static let patternSide: Int = 160

    private let queue = Queue(name: "org.telegram.walletCollectibleArtworks", qos: .userInitiated)
    private var values: [String: WalletCollectibleArtwork] = [:]
    private var promises: [String: Promise<WalletCollectibleArtwork>] = [:]
    private var requested: Set<String> = []
    private var requestedModels: [String: MediaId] = [:]
    private var requestedPatterns: [String: MediaId] = [:]
    private var disposableSets: [String: DisposableSet] = [:]

    func current(_ address: String) -> WalletCollectibleArtwork {
        return values[address] ?? WalletCollectibleArtwork()
    }

    func updates(_ address: String) -> Signal<WalletCollectibleArtwork, NoError> {
        return promise(address).get()
    }

    @available(macOS 10.15, *)
    func artwork(_ collectible: WalletContext.Collectible, context: any AccountContextProtocol, modelFile: Data? = nil) -> Signal<WalletCollectibleArtwork, NoError> {
        assert(Thread.isMainThread)
        let promise = self.promise(collectible.address)
        load(collectible, context: context, modelFile: modelFile)
        return promise.get()
    }

    @available(macOS 10.15, *)
    func preload(_ collectible: WalletContext.Collectible, context: any AccountContextProtocol, modelFile: Data?) {
        assert(Thread.isMainThread)
        load(collectible, context: context, modelFile: modelFile)
    }

    private func promise(_ address: String) -> Promise<WalletCollectibleArtwork> {
        if let current = promises[address] {
            return current
        }
        let promise = Promise<WalletCollectibleArtwork>(current(address))
        promises[address] = promise
        return promise
    }

    private func update(_ address: String, _ f: (inout WalletCollectibleArtwork) -> Void) {
        var value = current(address)
        f(&value)
        values[address] = value
        promise(address).set(.single(value))
    }

    private func disposables(_ address: String) -> DisposableSet {
        if let current = disposableSets[address] {
            return current
        }
        let set = DisposableSet()
        disposableSets[address] = set
        return set
    }

    @available(macOS 10.15, *)
    private func load(_ collectible: WalletContext.Collectible, context: any AccountContextProtocol, modelFile: Data?) {
        let address = collectible.address
        guard collectible.kind == .gift else {
            return
        }
        let postbox = context.account.postbox
        if let modelFile, current(address).modelFile == nil, let file = walletDecodedMediaFile(modelFile) {
            loadModel(file, address: address, postbox: postbox)
        }
        guard !requested.contains(address) else {
            return
        }
        requested.insert(address)
        if let gift = collectible.nft?.gift {
            apply(gift, address: address, postbox: postbox)
        } else if let slug = collectible.giftSlug {
            let gift = context.engine.payments.getUniqueStarGift(slug: slug)
            |> map(Optional.init)
            |> `catch` { _ -> Signal<StarGift.UniqueGift?, NoError> in
                return .single(nil)
            }
            |> deliverOnMainQueue
            disposables(address).add(gift.start(next: { [weak self] gift in
                guard let self else {
                    return
                }
                guard let gift else {
                    self.requested.remove(address)
                    return
                }
                self.apply(gift, address: address, postbox: postbox)
            }))
        }
    }

    private func apply(_ gift: StarGift.UniqueGift, address: String, postbox: Postbox) {
        var patternFile: TelegramMediaFile?
        for case let .pattern(_, file, _) in gift.attributes {
            patternFile = file
        }
        var styleSource: (inner: Int32, outer: Int32, pattern: Int32, patternFile: Data?)?
        for case let .backdrop(_, _, inner, outer, color, _, _) in gift.attributes {
            styleSource = (inner, outer, color, patternFile.map(walletEncodedMediaFile))
        }
        update(address) {
            $0.gift = gift
            $0.styleSource = styleSource
        }
        if let model = walletCollectibleModelFile(gift), current(address).modelFile == nil {
            loadModel(model, address: address, postbox: postbox)
        }
        if let patternFile {
            loadPattern(patternFile, address: address, postbox: postbox)
        }
    }

    private func loadModel(_ file: TelegramMediaFile, address: String, postbox: Postbox) {
        guard requestedModels[address] != file.fileId else {
            return
        }
        requestedModels[address] = file.fileId
        update(address) { $0.modelFile = walletEncodedMediaFile(file) }
        let side = WalletCollectibleArtworks.artSide
        let box = CGFloat(side) * (1 - WalletCollectibleArtworks.artInset * 2)
        disposables(address).add(frame(file, box: box, postbox: postbox).start(next: { [weak self] image in
            guard let canvas = walletCollectibleCanvas(image, side: side, inset: WalletCollectibleArtworks.artInset) else {
                return
            }
            self?.update(address) { $0.art = canvas }
        }))
    }

    private func loadPattern(_ file: TelegramMediaFile, address: String, postbox: Postbox) {
        guard requestedPatterns[address] != file.fileId else {
            return
        }
        requestedPatterns[address] = file.fileId
        let side = WalletCollectibleArtworks.patternSide
        disposables(address).add(frame(file, box: CGFloat(side), postbox: postbox).start(next: { [weak self] image in
            guard let canvas = walletCollectibleCanvas(image, side: side, inset: 0) else {
                return
            }
            self?.update(address) { $0.pattern = canvas }
        }))
    }

    private func frame(_ file: TelegramMediaFile, box: CGFloat, postbox: Postbox) -> Signal<CGImage, NoError> {
        let size = file.dimensions?.size.aspectFitted(NSMakeSize(box, box)) ?? NSMakeSize(box, box)
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets(), scale: 1.0)
        return chatMessageAnimatedSticker(postbox: postbox, file: walletCollectibleFileReference(file), small: false, scale: 1.0, size: size, fetched: true, thumbAtFrame: 0, isVideo: file.isVideoSticker)
        |> deliverOn(queue)
        |> mapToSignal { data -> Signal<CGImage, NoError> in
            guard data.data.fullSizeComplete, let frame = data.execute(arguments, data.data)?.generateImage() else {
                return .complete()
            }
            return .single(frame)
        }
        |> take(1)
        |> deliverOnMainQueue
    }
}

@available(macOS 10.15, *)
extension WalletCollectibleArtwork {
    var style: WalletContext.CardGiftStyle? {
        guard let styleSource else {
            return nil
        }
        return WalletContext.CardGiftStyle(innerColor: styleSource.inner, outerColor: styleSource.outer, patternColor: styleSource.pattern, patternFile: styleSource.patternFile)
    }
}
