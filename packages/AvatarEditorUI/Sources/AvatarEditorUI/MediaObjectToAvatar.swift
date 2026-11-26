import Foundation
import TelegramCore
import SwiftSignalKit
import TGUIKit
import CoreMedia
import libwebp
import Postbox
import ColorPalette
import ThemeSettings
import ObjcUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramContext
import AppKit

private func avatarPatternBackground(_ signal: Signal<ImageDataTransformation, NoError>, arguments: TransformImageArguments) -> Signal<CGImage, NoError> {
    signal |> filter { $0.data.fullSizeComplete } |> take(1) |> mapToSignal { value in
        guard let data = value.data.fullSizeData, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceCreateImageAtIndex(source, 0, nil) != nil, let image = value.execute(arguments, value.data)?.generateImage() else { return .complete() }
        return .single(image)
    }
}

private final class StickerToMp4Context {
    private let statusPromise: ValuePromise<StickerToMp4.Status> = ValuePromise(ignoreRepeated: true)
    
    public var statusValue: Signal<StickerToMp4.Status, NoError> {
        return statusPromise.get()
    }
    
    public static let queue: Queue = Queue(name: "org.telegram.sticker-to-mp4")
    
    private var status: StickerToMp4.Status = .initializing("") {
        didSet {
            statusPromise.set(status)
        }
    }
    
    
    private let export: AvatarVideoExport?
    private let cancelled: Atomic<Bool>
    private var started = false
    private var processingStarted = false
    private var completed = false
    private var thumbnailPath: String?

    private let dataDisposable = MetaDisposable()
    private let fileReference: FileMediaReference
    private let context: any AccountContextProtocol
    private let background: Signal<CGImage, NoError>
    private let zoom: CGFloat
    private let offset: CGPoint
    public init(context: any AccountContextProtocol, background: Signal<CGImage, NoError>, zoom: CGFloat, offset: CGPoint, fileReference: FileMediaReference, codec: String, cancelled: Atomic<Bool>) {
        self.export = try? AvatarVideoExport(codec: codec)
        self.cancelled = cancelled
        self.context = context
        self.background = background
        self.fileReference = fileReference
        self.zoom = zoom
        self.offset = offset
    }
    
    deinit {
        dataDisposable.dispose()
        export?.cancel()
        if let thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbnailPath)
        }
    }

    public func start() {
        guard !self.started, !self.cancelled.with({ $0 }) else { return }
        self.started = true
        guard self.export != nil else {
            self.finish(path: nil)
            return
        }
        let signal = avatarMediaResourcePath(context: self.context, fileReference: self.fileReference)
        let type: LottieAnimationType
        if fileReference.media.isWebm {
            type = .webm
        } else if fileReference.media.mimeType == "image/webp" {
            type = .webp
        } else {
            type = .lottie
        }
        dataDisposable.set((combineLatest(signal, background |> castError(AvatarMediaPreparationError.self) |> then(.fail(.generic)) |> take(1)) |> take(1) |> deliverOn(StickerToMp4Context.queue)).start(next: { [weak self] path, background in
            guard let self, !self.cancelled.with({ $0 }), !self.completed else { return }
            self.processingStarted = true
            let data: Data?
            switch type {
            case .webm:
                data = path.data(using: .utf8)
            default:
                data = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
            guard let data else {
                self.finish(path: nil)
                return
            }
            let animation = LottieAnimation(compressed: data, key: .init(key: .bundle("_convert_file_\(path)"), size: NSMakeSize(640, 640)), type: type)
            self.process(animation, background: background)
        }, error: { [weak self] _ in
            self?.finish(path: nil)
        }, completed: { [weak self] in
            guard let self, !self.processingStarted else { return }
            self.finish(path: nil)
        }))
    }

    private func process(_ lottie: LottieAnimation, background: CGImage) {
        guard !self.completed, !self.cancelled.with({ $0 }), let export = self.export, let renderer = lottie.initialize() else {
            self.finish(path: nil)
            return
        }
        let fps: Int
        switch lottie.type {
        case .lottie:
            fps = renderer.mainFps
        default:
            fps = renderer.fps
        }
        guard var sequence = AvatarVideoFrameSequence(startFrame: renderer.startFrame, endFrame: renderer.endFrame, fps: fps), let firstFrame = renderer.render(at: renderer.startFrame, frames: [], previousFrame: nil), let image = firstFrame.image else {
            self.finish(path: nil)
            return
        }
        let thumbPath = NSTemporaryDirectory() + "tgs_\(UUID().uuidString).jpg"
        self.thumbnailPath = thumbPath
        guard let thumbnail = avatarCompositedImage(from: image, zoom: self.zoom, offset: self.offset, background: background) else {
            self.finish(path: nil)
            return
        }
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: thumbPath) as CFURL, kUTTypeJPEG, 1, nil) else {
            self.finish(path: nil)
            return
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            self.finish(path: nil)
            return
        }
        self.status = .initializing(thumbPath)
        var previousFrame: RenderedFrame? = firstFrame
        let cancelled = self.cancelled
        export.start(queue: Self.queue.queue, isCancelled: { cancelled.with { $0 } }, next: { [weak self] in
            guard let self, !self.completed, !cancelled.with({ $0 }) else { return .failed }
            guard let sample = sequence.next() else { return .finished(sequence.duration) }
            let rendered = sample.frame == renderer.startFrame ? firstFrame : renderer.render(at: sample.frame, frames: [], previousFrame: previousFrame)
            guard let rendered, let image = rendered.image else {
                if lottie.type == .webm, sample.frame >= renderer.endFrame, sample.time > .zero {
                    return .finished(sample.time)
                }
                return .failed
            }
            previousFrame = rendered
            guard let pixelBuffer = avatarPixelBuffer(from: image, zoom: self.zoom, offset: self.offset, background: background) else { return .failed }
            self.status = .converting(sample.progress)
            return .frame(pixelBuffer, sample.time)
        }, completed: { [weak self] path in
            self?.finish(path: path)
        })
    }

    private func finish(path: String?) {
        guard !self.completed else { return }
        self.completed = true
        self.dataDisposable.dispose()
        if let path, let thumbnailPath = self.thumbnailPath, !self.cancelled.with({ $0 }) {
            self.thumbnailPath = nil
            self.status = .done(path, thumbnailPath)
        } else {
            if let path {
                try? FileManager.default.removeItem(atPath: path)
            }
            self.export?.cancel()
            if let thumbnailPath = self.thumbnailPath {
                self.thumbnailPath = nil
                try? FileManager.default.removeItem(atPath: thumbnailPath)
            }
            self.status = .failed
        }
    }

    public func cancel() {
        _ = self.cancelled.swap(true)
        self.finish(path: nil)
    }

}



private final class StickerToMp4 {
    
    public enum Status : Equatable {
        case initializing(String)
        case converting(Float)
        case done(String, String)
        case failed
    }
    
    private let cancelled = Atomic(value: false)
    private let context:QueueLocalObject<StickerToMp4Context>
    public init(context _context: any AccountContextProtocol, background: Signal<CGImage, NoError>, zoom: CGFloat, offset: CGPoint, fileReference: FileMediaReference, codec: String) {
        let cancelled = self.cancelled
        self.context = .init(queue: StickerToMp4Context.queue, generate: {
            return StickerToMp4Context(context: _context, background: background, zoom: zoom, offset: offset, fileReference: fileReference, codec: codec, cancelled: cancelled)
        })
    }
    
    
    public func start() {
        self.context.with {
            $0.start()
        }
    }
    
    public func cancel() {
        _ = self.cancelled.swap(true)
        self.context.with {
            $0.cancel()
        }
    }
    
    deinit {
        _ = self.cancelled.swap(true)
        self.context.with { $0.cancel() }
    }

    public var status:Signal<Status, NoError> {
        return self.context.signalWith { context, subscriber in
            return context.statusValue.start(next: { next in
                subscriber.putNext(next)
            }, completed: {
                subscriber.putCompletion()
            })
        }
    }
}


private final class FetchVideoToFile {
    private let statusValue = ValuePromise<Result<AvatarPreparedVideo, AvatarMediaPreparationError>>()
    public var status: Signal<Result<AvatarPreparedVideo, AvatarMediaPreparationError>, NoError> {
        self.statusValue.get() |> take(1)
    }
    private let context: any AccountContextProtocol
    private let file: TelegramMediaFile
    private let disposable = MetaDisposable()
    private var started = false

    init(context: any AccountContextProtocol, file: TelegramMediaFile) {
        self.context = context
        self.file = file
    }

    deinit {
        self.disposable.dispose()
    }

    func start() {
        guard !self.started else { return }
        self.started = true
        self.disposable.set((avatarMediaResourcePath(context: self.context, fileReference: .standalone(media: self.file)) |> deliverOn(StickerToMp4Context.queue)).start(next: { [weak self] path in
            guard let self else { return }
            self.statusValue.set(AvatarPreparedVideo.prepare(path: path))
        }, error: { [weak self] _ in
            self?.statusValue.set(.failure(.generic))
        }))
    }
}

private final class FetchStickerToImage {
    private let statusValue = ValuePromise<Result<NSImage, AvatarMediaPreparationError>>()
    public var status: Signal<Result<NSImage, AvatarMediaPreparationError>, NoError> {
        self.statusValue.get() |> take(1)
    }
    private let context: any AccountContextProtocol
    private let file: TelegramMediaFile
    private let disposable = MetaDisposable()
    private let background: Signal<CGImage, NoError>
    private let zoom: CGFloat
    private let offset: CGPoint
    private var started = false
    private var completed = false

    init(context: any AccountContextProtocol, background: Signal<CGImage, NoError>, zoom: CGFloat, offset: CGPoint, file: TelegramMediaFile) {
        self.context = context
        self.file = file
        self.background = background
        self.zoom = zoom
        self.offset = offset
    }

    deinit {
        self.disposable.dispose()
    }

    func start() {
        guard !self.started else { return }
        self.started = true
        let resource = avatarMediaResourcePath(context: self.context, fileReference: .standalone(media: self.file))
        self.disposable.set((combineLatest(self.background |> castError(AvatarMediaPreparationError.self) |> then(.fail(.generic)) |> take(1), resource) |> take(1) |> deliverOn(StickerToMp4Context.queue)).start(next: { [weak self] background, path in
            guard let self else { return }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let webp = convertFromWebP(data)?._cgImage else {
                self.finish(.failure(.generic))
                return
            }
            guard let image = avatarCompositedImage(from: webp, zoom: self.zoom, offset: self.offset, background: background) else {
                self.finish(.failure(.generic))
                return
            }
            self.finish(.success(NSImage(cgImage: image, size: image.size)))
        }, error: { [weak self] _ in
            self?.finish(.failure(.generic))
        }, completed: { [weak self] in
            self?.finish(.failure(.generic))
        }))
    }

    private func finish(_ result: Result<NSImage, AvatarMediaPreparationError>) {
        guard !self.completed else { return }
        self.completed = true
        self.statusValue.set(result)
    }
}

public final class MediaObjectToAvatar {
    public struct Object {
        public struct Foreground {
            public enum Source {
                case emoji(String, NSColor)
                case sticker(TelegramMediaFile)
                case animated(TelegramMediaFile)
                case gif(TelegramMediaFile)
            }
            public var type: Source
            public var zoom: CGFloat
            public var offset: CGPoint
            public init(type: Source, zoom: CGFloat, offset: CGPoint) {
                self.type = type
                self.zoom = zoom
                self.offset = offset
            }
        }
        public enum Background {
            case colors([NSColor])
            case pattern(Wallpaper, ColorPalette)
        }
        public let foreground: Foreground
        public let background: Background
        public init(foreground: Foreground, background: Background) {
            self.foreground = foreground
            self.background = background
        }
    }
    
    public struct Result {
        public enum Status {
            case initializing(String)
            case converting(Float)
            case done(String, String)
            case failed
        }
        public enum Result {
            case image(NSImage)
            case video(String, String)
        }
        public var status: Status?
        public var result: Result?
    }
    
    
    
    private var animated_c:StickerToMp4?

    private var fetch_v: FetchVideoToFile?
    private var fetch_i: FetchStickerToImage?

    public let object: Object
    private let context: any AccountContextProtocol
    
    private let codec: String
    
    public init(context: any AccountContextProtocol, object: Object, codec: String = AVVideoCodecType.h264.rawValue) {
        self.object = object
        self.context = context
        self.codec = codec
    }
  
    public func start() -> Signal<Result, NoError> {
        let context = self.context
        let object = self.object
        let codec = self.codec
        return Signal { subscriber in
            let operation = MediaObjectToAvatar(context: context, object: object, codec: codec)
            let signal = operation.generate() |> then(.single(Result(status: .failed, result: nil))) |> take(until: { value in
                let terminal: Bool
                if case .failed = value.status {
                    terminal = true
                } else {
                    terminal = value.result != nil
                }
                return SignalTakeAction(passthrough: true, complete: terminal)
            })
            let disposable = signal.start(next: { subscriber.putNext($0) }, completed: { subscriber.putCompletion() })
            return ActionDisposable {
                disposable.dispose()
                withExtendedLifetime(operation) {}
            }
        }
    }

    private func generate() -> Signal<Result, NoError> {
        guard avatarDrawingFrame(size: CGSize(width: 640, height: 640), zoom: self.object.foreground.zoom, offset: self.object.foreground.offset) != nil else {
            return .single(.init(status: .failed, result: nil))
        }
        let background: Signal<CGImage, NoError>

        switch object.background {
        case let .colors(colors):
            background = Signal { subscriber in
                let image = avatarDrawingImage(size: CGSize(width: 640, height: 640)) { size, ctx in
                    ctx.clear(size.bounds)
                    let imageRect = size.bounds
                    if colors.count == 1, let color = colors.first {
                        ctx.setFillColor(color.cgColor)
                        ctx.fill(imageRect)
                    } else if colors.count > 1 {
                        guard let gradient = CGGradient.evenlySpaced(colors) else { return false }
                                            
                        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: imageRect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    }
                    return true
                }
                if let image {
                    subscriber.putNext(image)
                }
                subscriber.putCompletion()
                return EmptyDisposable
            }
        case let .pattern(wallpaper, palette):
            let emptyColor: TransformImageEmptyColor
            
            let colors = wallpaper.settings.colors.compactMap { NSColor($0) }
            
            if colors.count > 1 {
                let colors = colors.map {
                    return $0.withAlphaComponent($0.alpha == 0 ? 0.5 : $0.alpha)
                }
                emptyColor = .gradient(colors: colors, intensity: colors.first!.alpha, rotation: nil)
            } else if let color = colors.first {
                emptyColor = .color(color)
            } else {
                emptyColor = .color(NSColor(rgb: 0xd6e2ee, alpha: 0.5))
            }
            
            let arguments = TransformImageArguments(corners: ImageCorners(radius: 0), imageSize: wallpaper.dimensions.aspectFilled(NSMakeSize(640, 640)), boundingSize: NSMakeSize(640, 640), intrinsicInsets: NSEdgeInsets(), emptyColor: emptyColor)
            
            switch wallpaper {
            case let .file(_, file, _, _, _):
                var representations:[TelegramMediaImageRepresentation] = []
                if let dimensions = file.dimensions {
                    representations.append(TelegramMediaImageRepresentation(dimensions: dimensions, resource: file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                } else {
                    representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(NSMakeSize(640, 640)), resource: file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                }

                let updateImageSignal = chatWallpaper(account: context.account, representations: representations, file: file, mode: .thumbnail, isPattern: true, autoFetchFullSize: true, scale: 2, isBlurred: false, synchronousLoad: false, drawPatternOnly: false, palette: palette)

                background = avatarPatternBackground(updateImageSignal, arguments: arguments)
                
            default:
                background = .complete()
            }
        }
        
        let signal: Signal<Result, NoError>
        let zoom = object.foreground.zoom
        switch object.foreground.type {
        case let .animated(file):
            let stickerToMp4: StickerToMp4 = .init(context: context, background: background, zoom: object.foreground.zoom, offset: object.foreground.offset, fileReference: .standalone(media: file), codec: codec)
            self.animated_c = stickerToMp4
            
            signal = stickerToMp4.status |> map { value -> Result in
                switch value {
                case let .initializing(path):
                    return .init(status: .initializing(path), result: nil)
                case .failed:
                    return .init(status: .failed, result: nil)
                case let .done(path, thumb):
                    return .init(status: .done(path, thumb), result: .video(path, thumb))
                case let .converting(progress):
                    return .init(status: .converting(progress), result: nil)
                }
            }
            stickerToMp4.start()
        case let .emoji(text, color):
            signal = background |> mapToSignal { value in
                let emoji = avatarDrawingImage(size: CGSize(width: 640, height: 640), flipped: true) { size, ctx in
                    ctx.clear(size.bounds)
                    
                    ctx.setFillColor(.white)
                    ctx.fill(size.bounds)
                    
                    let textNode = TextNode.layoutText(.initialize(string: text, color: color, font: .avatar(150 * zoom + 150)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)

                    ctx.draw(value, in: size.bounds)
                    
                    var rect = size.bounds.focus(textNode.0.size)
                    rect.origin.y += 4
                    textNode.1.draw(rect, in: ctx, backingScaleFactor: 1.0, backgroundColor: .white)
                    
                    return true
                }
                guard let emoji else { return .single(.init(status: .failed, result: nil)) }
                return .single(.init(status: nil, result: .image(NSImage(cgImage: emoji, size: emoji.size))))
            }
            
        case let .gif(file):
            let fetch_v = FetchVideoToFile(context: context, file: file)
            self.fetch_v = fetch_v
            signal = fetch_v.status |> map { result in
                switch result {
                case let .success(video):
                    let files = video.takeFiles()
                    return .init(status: nil, result: .video(files.video, files.thumbnail))
                case .failure:
                    return .init(status: .failed, result: nil)
                }
            }
            fetch_v.start()
        case let .sticker(file):
            let fetch_i = FetchStickerToImage(context: context, background: background, zoom: object.foreground.zoom, offset: object.foreground.offset, file: file)
            self.fetch_i = fetch_i
            signal = fetch_i.status |> map { result in
                switch result {
                case let .success(image):
                    return .init(status: nil, result: .image(image))
                case .failure:
                    return .init(status: .failed, result: nil)
                }
            }
            fetch_i.start()
        }
        return signal
    }
}
