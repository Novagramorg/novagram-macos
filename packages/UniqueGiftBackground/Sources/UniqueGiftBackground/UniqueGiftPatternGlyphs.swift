import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramUtils
import TelegramContext
import UniqueGiftRenderer

public final class UniqueGiftPatternGlyphs {
    public static let shared = UniqueGiftPatternGlyphs()

    private static let capacity = 64
    private static let queue = Queue(name: "org.telegram.uniqueGiftPatternGlyphs", qos: .userInitiated)

    private var glyphs: [Int64: UniqueGiftGlyph] = [:]
    private var recent: [Int64] = []
    private var loading: [Int64: (disposable: Disposable, subscribers: Bag<(UniqueGiftGlyph) -> Void>)] = [:]

    public func cachedGlyph(fileId: Int64) -> UniqueGiftGlyph? {
        assert(Thread.isMainThread)
        return self.glyphs[fileId]
    }

    public func glyph(context: any AccountContextProtocol, pattern: UniqueGiftBackgroundContent.Pattern) -> Signal<UniqueGiftGlyph, NoError> {
        let fileId = pattern.fileId
        return Signal { [weak self] subscriber in
            assert(Thread.isMainThread)
            guard let self = self else {
                return EmptyDisposable
            }
            if let glyph = self.glyphs[fileId] {
                subscriber.putNext(glyph)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let index: Int
            if let loading = self.loading[fileId] {
                index = loading.subscribers.add({ glyph in
                    subscriber.putNext(glyph)
                    subscriber.putCompletion()
                })
            } else {
                let subscribers = Bag<(UniqueGiftGlyph) -> Void>()
                index = subscribers.add({ glyph in
                    subscriber.putNext(glyph)
                    subscriber.putCompletion()
                })
                let disposable = MetaDisposable()
                self.loading[fileId] = (disposable, subscribers)
                disposable.set((UniqueGiftPatternGlyphs.load(context: context, pattern: pattern) |> deliverOnMainQueue).start(next: { [weak self] glyph in
                    self?.complete(fileId: fileId, glyph: glyph)
                }))
            }
            return ActionDisposable { [weak self] in
                Queue.mainQueue().async {
                    guard let self = self, let loading = self.loading[fileId] else {
                        return
                    }
                    loading.subscribers.remove(index)
                    if loading.subscribers.isEmpty {
                        loading.disposable.dispose()
                        self.loading.removeValue(forKey: fileId)
                    }
                }
            }
        } |> runOn(Queue.mainQueue())
    }

    public func removeAll() {
        assert(Thread.isMainThread)
        self.glyphs.removeAll()
        self.recent.removeAll()
    }

    private func complete(fileId: Int64, glyph: UniqueGiftGlyph) {
        self.glyphs[fileId] = glyph
        self.recent.removeAll(where: { $0 == fileId })
        self.recent.append(fileId)
        if self.recent.count > UniqueGiftPatternGlyphs.capacity {
            self.glyphs.removeValue(forKey: self.recent.removeFirst())
        }
        guard let loading = self.loading.removeValue(forKey: fileId) else {
            return
        }
        loading.disposable.dispose()
        for subscriber in loading.subscribers.copyItems() {
            subscriber(glyph)
        }
    }

    private static func reference(for file: TelegramMediaFile) -> FileMediaReference {
        for attribute in file.attributes {
            switch attribute {
            case let .Sticker(_, packReference, _):
                if let packReference = packReference {
                    return .stickerPack(stickerPack: packReference, media: file)
                }
            case let .CustomEmoji(_, _, _, packReference):
                if let packReference = packReference {
                    return .stickerPack(stickerPack: packReference, media: file)
                }
            default:
                break
            }
        }
        return .standalone(media: file)
    }

    private static func load(context: any AccountContextProtocol, pattern: UniqueGiftBackgroundContent.Pattern) -> Signal<UniqueGiftGlyph, NoError> {
        let file: Signal<TelegramMediaFile?, NoError>
        switch pattern {
        case let .file(value):
            file = .single(value)
        case let .fileId(id):
            file = context.engine.stickers.resolveInlineStickers(fileIds: [id]) |> map { $0[id] } |> take(1)
        }
        let postbox = context.account.postbox
        return file |> mapToSignal { file -> Signal<UniqueGiftGlyph, NoError> in
            guard let file = file else {
                return .never()
            }
            let pixelSize = CGFloat(UniqueGiftBackgroundRenderer.glyphPixelSize)
            let size = NSMakeSize(pixelSize, pixelSize)
            let aspectSize = file.dimensions?.size.aspectFitted(size) ?? size
            let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: aspectSize, intrinsicInsets: NSEdgeInsets(), scale: 1.0)
            return chatMessageAnimatedSticker(postbox: postbox, file: UniqueGiftPatternGlyphs.reference(for: file), small: false, scale: 1.0, size: aspectSize, fetched: true, thumbAtFrame: 0, isVideo: file.isVideoSticker)
                |> deliverOn(UniqueGiftPatternGlyphs.queue)
                |> mapToSignal { data -> Signal<UniqueGiftGlyph, NoError> in
                    guard data.data.fullSizeComplete, let image = data.execute(arguments, data.data)?.generateImage(), let glyph = UniqueGiftGlyph(image: image) else {
                        return .complete()
                    }
                    return .single(glyph)
                }
                |> take(1)
        }
    }
}
