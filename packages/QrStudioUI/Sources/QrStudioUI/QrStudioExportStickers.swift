import Foundation
import AppKit
import ImageIO
import SwiftSignalKit
import Postbox
import TelegramCore
import TGUIKit
import TelegramContext
import TelegramMedia

final class QrStudioExportSticker {
    let frames: [CGImage]
    let period: Double

    init(frames: [CGImage], period: Double) {
        self.frames = frames
        self.period = period
    }

    var isAnimated: Bool {
        return self.frames.count > 1 && self.period > 0.0
    }

    func image(phase: Double, at t: Double) -> CGImage? {
        guard !self.frames.isEmpty else {
            return nil
        }
        return self.frames[QrStudioExportMotion.frameIndex(frameCount: self.frames.count, period: self.period, phase: phase, at: t)]
    }
}

private let qrStudioExportMaxFrames = 600

func qrStudioDecodeExportPlane(pixelSide: Int) -> QrStudioExportSticker? {
    guard pixelSide > 0, let data = NSDataAsset(name: "PlaneLogoPlain")?.data else {
        return nil
    }
    let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .bundle("qr_studio_plane"), size: CGSize(width: CGFloat(pixelSide), height: CGFloat(pixelSide)), backingScale: 1), type: .lottie, cachePurpose: .none, metalSupport: false)
    guard let renderer = animation.initialize() else {
        return nil
    }
    let frameCount = Int(renderer.endFrame - renderer.startFrame)
    guard frameCount > 0 else {
        return nil
    }
    let frameRate = max(1, renderer.mainFps)
    let step = QrStudioExportMotion.frameStep(frameDuration: 1.0 / Double(frameRate))
    var frames: [CGImage] = []
    var index = 0
    while index < frameCount {
        if let image = renderer.render(at: renderer.startFrame + Int32(index), frames: [], previousFrame: nil)?.image, let tinted = qrStudioTinted(image, color: .white) {
            frames.append(tinted)
        }
        index += step
    }
    guard !frames.isEmpty else {
        return nil
    }
    return QrStudioExportSticker(frames: frames, period: Double(frameCount) / Double(frameRate))
}

func qrStudioExportCGImage(rgba data: Data, width: Int, height: Int, bytesPerRow: Int) -> CGImage? {
    guard width > 0, height > 0, bytesPerRow >= width * 4, data.count >= height * bytesPerRow else {
        return nil
    }
    let settings = DeviceGraphicsContextSettings.shared
    let copy = data.subdata(in: 0 ..< height * bytesPerRow)
    guard let provider = CGDataProvider(data: copy as CFData) else {
        return nil
    }
    return CGImage(width: width, height: height, bitsPerComponent: settings.bitsPerComponent, bitsPerPixel: settings.bitsPerPixel, bytesPerRow: bytesPerRow, space: settings.colorSpace, bitmapInfo: settings.opaqueBitmapInfo, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}

private func qrStudioExportSquared(_ image: CGImage, side: Int) -> CGImage? {
    guard image.width > 0, image.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        return nil
    }
    let scale = min(CGFloat(side) / CGFloat(image.width), CGFloat(side) / CGFloat(image.height))
    let width = CGFloat(image.width) * scale
    let height = CGFloat(image.height) * scale
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: side, height: side))
    context.draw(image, in: CGRect(x: (CGFloat(side) - width) * 0.5, y: (CGFloat(side) - height) * 0.5, width: width, height: height))
    return context.makeImage()
}

private func qrStudioExportFrame(_ image: CGImage, side: Int, tint: NSColor?) -> CGImage? {
    var result = image
    if image.width != side || image.height != side {
        guard let squared = qrStudioExportSquared(image, side: side) else {
            return nil
        }
        result = squared
    }
    if let tint = tint {
        return qrStudioTinted(result, color: tint)
    }
    return result
}

private func qrStudioExportStill(path: String, pixelSide: Int, tint: NSColor?) -> QrStudioExportSticker? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let frame = qrStudioExportFrame(image, side: pixelSide, tint: tint) else {
        return nil
    }
    return QrStudioExportSticker(frames: [frame], period: 0.0)
}

private func qrStudioExportFrames(file: TelegramMediaFile, path: String, pixelSide: Int, tint: NSColor?, firstFrameOnly: Bool) -> QrStudioExportSticker? {
    let type: LottieAnimationType
    let data: Data
    var renderSize = CGSize(width: CGFloat(pixelSide), height: CGFloat(pixelSide))
    if file.mimeType == "video/webm" {
        guard let value = path.data(using: .utf8) else {
            return nil
        }
        type = .webm
        data = value
        if let dimensions = file.dimensions, dimensions.width > 0, dimensions.height > 0 {
            let scale = CGFloat(pixelSide) / CGFloat(max(dimensions.width, dimensions.height))
            renderSize = CGSize(width: max(1.0, (CGFloat(dimensions.width) * scale).rounded()), height: max(1.0, (CGFloat(dimensions.height) * scale).rounded()))
        }
    } else if file.mimeType == "image/webp" {
        guard let value = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return nil
        }
        type = .webp
        data = value
    } else if file.mimeType.hasPrefix("image/") {
        return qrStudioExportStill(path: path, pixelSide: pixelSide, tint: tint)
    } else {
        guard let value = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return nil
        }
        type = .lottie
        data = value
    }

    let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .media(file.fileId), size: renderSize, backingScale: 1), type: type, cachePurpose: .none, metalSupport: false)
    guard let renderer = animation.initialize() else {
        return nil
    }

    let start = renderer.startFrame
    let total: Int
    let fixedDuration: Double?
    switch type {
    case .lottie:
        total = max(1, Int(renderer.endFrame - renderer.startFrame))
        fixedDuration = 1.0 / Double(renderer.mainFps > 0 ? renderer.mainFps : 60)
    case .webm:
        total = qrStudioExportMaxFrames
        fixedDuration = 1.0 / Double(renderer.fps > 0 ? renderer.fps : 30)
    case .webp:
        total = max(1, Int(renderer.endFrame - renderer.startFrame))
        fixedDuration = nil
    }
    let limit = firstFrameOnly ? 1 : min(total, qrStudioExportMaxFrames)

    var frames: [CGImage] = []
    var period: Double = 0.0
    var step = 1
    var index = 0
    while index < limit {
        if index % step != 0, type == .lottie, let fixedDuration = fixedDuration {
            period += fixedDuration
            index += 1
            continue
        }
        guard let rendered = renderer.render(at: start + Int32(index), frames: [], previousFrame: nil) else {
            break
        }
        let duration = fixedDuration ?? rendered.duration
        if index == 0 {
            step = QrStudioExportMotion.frameStep(frameDuration: duration)
        }
        period += duration
        if index % step == 0, let image = rendered.image, let frame = qrStudioExportFrame(image, side: pixelSide, tint: tint) {
            frames.append(frame)
        }
        index += 1
    }
    if frames.isEmpty {
        return nil
    }
    return QrStudioExportSticker(frames: frames, period: frames.count > 1 ? period : 0.0)
}

private func qrStudioExportResourcePath(context: any AccountContextProtocol, file: TelegramMediaFile) -> Signal<String?, NoError> {
    let mediaBox = context.account.postbox.mediaBox
    let reference = FileMediaReference.standalone(media: file).resourceReference(file.resource)
    return Signal { subscriber in
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .other, userContentType: .sticker, reference: reference).start()
        let data = (mediaBox.resourceData(file.resource)
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            subscriber.putNext(data.path)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetch.dispose()
            data.dispose()
        }
    }
}

private let qrStudioExportDecodeQueue = Queue(name: "org.telegram.QrStudioExportDecode", qos: .userInitiated)

private let qrStudioPreviewDecodeQueue = Queue(name: "org.telegram.QrStudioPreviewDecode", qos: .userInteractive)

func qrStudioDecodeExportSticker(context: any AccountContextProtocol, file: TelegramMediaFile, pixelSide: Int, tint: NSColor?, firstFrameOnly: Bool) -> Signal<QrStudioExportSticker?, NoError> {
    guard pixelSide > 0 else {
        return .single(nil)
    }
    let paint: NSColor? = tint ?? (file.isCustomTemplateEmoji ? NSColor.white : nil)
    let queue = firstFrameOnly ? qrStudioPreviewDecodeQueue : qrStudioExportDecodeQueue
    return qrStudioExportResourcePath(context: context, file: file)
    |> timeout(10.0, queue: queue, alternate: .single(nil))
    |> deliverOn(queue)
    |> map { path -> QrStudioExportSticker? in
        guard let path = path else {
            return nil
        }
        return qrStudioExportFrames(file: file, path: path, pixelSide: pixelSide, tint: paint, firstFrameOnly: firstFrameOnly)
    }
}
