import Cocoa
import SwiftSignalKit
import TGUIKit
import Accelerate
import CoreMedia
import AVFoundation

private func videoEditorThumbnailSize(_ size: CGSize) -> CGSize? {
    let size = size.multipliedByScreenScale()
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, size.width <= 4096, size.height <= 4096 else { return nil }
    return CGSize(width: ceil(size.width), height: ceil(size.height))
}

private func videoEditorThumbnailTimes(duration: CMTime, count: Int) -> [CMTime]? {
    guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0, count > 0, count <= 4096 else { return nil }
    var times: [CMTime] = []
    for index in 0 ..< count {
        let time = CMTimeMultiplyByRatio(duration, multiplier: Int32(index), divisor: Int32(count))
        guard time.isNumeric, CMTimeCompare(time, .zero) >= 0 else { return nil }
        times.append(CMTimeCompare(time, duration) < 0 ? time : (times.last ?? .zero))
    }
    return times
}

private func videoEditorThumbnailImage(_ image: CGImage, size: CGSize, blurred: Bool) -> CGImage? {
    let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
    let width = max(1, Int(floor(CGFloat(image.width) * scale)))
    let height = max(1, Int(floor(CGFloat(image.height) * scale)))
    let bytesPerRow = width * 4
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    if blurred {
        guard let data = context.data, let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let outputData = output.data else { return nil }
        var source = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        var destination = vImage_Buffer(data: outputData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        guard vImageBoxConvolve_ARGB8888(&source, &destination, nil, 0, 0, 15, 15, nil, vImage_Flags(kvImageEdgeExtend)) == kvImageNoError else { return nil }
        return output.makeImage()
    }
    return context.makeImage()
}

private final class VideoEditorImageRequest {
    private let queue = Queue(name: "org.telegram.video-editor-thumbnails")
    private let cancelled = Atomic(value: false)
    private let asset: AVAsset
    private let composition: AVVideoComposition?
    private let size: CGSize
    private let times: () -> [CMTime]?
    private let gradually: Bool
    private var updated: (([CGImage?], Bool) -> Void)?
    private var generator: AVAssetImageGenerator?
    private var requested: [(time: CMTime, indices: [Int])] = []
    private var completed: Set<Int> = []
    private var images: [CGImage?] = []
    private var finished = false

    init(asset: AVAsset, composition: AVVideoComposition?, size: CGSize, times: @escaping () -> [CMTime]?, gradually: Bool, updated: @escaping ([CGImage?], Bool) -> Void) {
        self.asset = asset
        self.composition = composition
        self.size = size
        self.times = times
        self.gradually = gradually
        self.updated = updated
    }

    func start() {
        self.queue.justDispatch { [weak self] in
            guard let self, !self.cancelled.with({ $0 }) else { return }
            guard let times = self.times(), !times.isEmpty else {
                self.finish()
                return
            }
            self.images = Array(repeating: nil, count: times.count)
            for (index, time) in times.enumerated() {
                if let existing = self.requested.last, CMTimeCompare(existing.time, time) == 0 {
                    self.requested[self.requested.count - 1].indices.append(index)
                } else {
                    self.requested.append((time, [index]))
                }
            }
            guard !self.cancelled.with({ $0 }) else { return }
            let generator = AVAssetImageGenerator(asset: self.asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = self.size
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.videoComposition = self.composition
            self.generator = generator
            generator.generateCGImagesAsynchronously(forTimes: self.requested.map { NSValue(time: $0.time) }) { [weak self] time, image, _, result, _ in
                guard let self, !self.cancelled.with({ $0 }) else { return }
                self.queue.justDispatch { [weak self] in
                    self?.receive(time: time, image: result == .succeeded ? image : nil)
                }
            }
        }
    }

    private func receive(time: CMTime, image: CGImage?) {
        guard !self.finished, !self.cancelled.with({ $0 }), time.isNumeric, let index = self.requested.firstIndex(where: { CMTimeCompare($0.time, time) == 0 }), self.completed.insert(index).inserted else { return }
        for slot in self.requested[index].indices {
            self.images[slot] = image
        }
        if self.completed.count == self.requested.count {
            self.finish()
        } else if self.gradually {
            self.updated?(self.images, false)
        }
    }

    private func finish() {
        guard !self.finished, !self.cancelled.with({ $0 }) else { return }
        self.finished = true
        let updated = self.updated
        self.updated = nil
        self.generator = nil
        updated?(self.images, true)
        self.images.removeAll()
    }

    func cancel() {
        guard !self.cancelled.swap(true) else { return }
        self.queue.justDispatch {
            self.updated = nil
            self.generator?.cancelAllCGImageGeneration()
            self.generator = nil
            self.images.removeAll()
        }
    }
}

public func generateVideoScrubberThumbs(for asset: AVAsset, composition: AVVideoComposition?, size: NSSize, count: Int, gradually: Bool, blur: Bool) -> Signal<([CGImage], Bool), NoError> {
    return Signal { subscriber in
        guard let size = videoEditorThumbnailSize(size), count > 0, count <= 4096 else {
            subscriber.putNext(([], true))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        var placeholder: CGImage?
        let request = VideoEditorImageRequest(asset: asset, composition: composition, size: size, times: {
            videoEditorThumbnailTimes(duration: asset.duration, count: count)
        }, gradually: gradually, updated: { images, complete in
            let available = images.indices.filter { images[$0] != nil }
            let frames: [CGImage]
            if let first = available.first, let fallbackImage = images[first] {
                if blur, placeholder == nil, images.contains(where: { $0 == nil }) {
                    placeholder = videoEditorThumbnailImage(fallbackImage, size: size, blurred: true) ?? fallbackImage
                }
                frames = images.enumerated().map { index, image in
                    if let image { return image }
                    if let placeholder { return placeholder }
                    let nearest = available.min(by: { abs($0 - index) < abs($1 - index) }) ?? first
                    return images[nearest] ?? fallbackImage
                }
            } else {
                frames = []
            }
            subscriber.putNext((frames, complete))
            if complete {
                subscriber.putCompletion()
            }
        })
        request.start()
        return ActionDisposable { request.cancel() }
    }
}

public func generateVideoAvatarPreview(for asset: AVComposition, composition: AVVideoComposition?, highSize: NSSize, lowSize: NSSize, at seconds: Double) -> Signal<(CGImage?, CGImage?), NoError> {
    return Signal { subscriber in
        guard let highSize = videoEditorThumbnailSize(highSize), let lowSize = videoEditorThumbnailSize(lowSize), seconds.isFinite, seconds >= 0 else {
            subscriber.putNext((nil, nil))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let request = VideoEditorImageRequest(asset: asset, composition: composition, size: highSize, times: {
            let duration = asset.duration
            guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0, seconds < duration.seconds else { return nil }
            let time = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
            guard time.isNumeric, CMTimeCompare(time, .zero) >= 0, CMTimeCompare(time, duration) < 0 else { return nil }
            return [time]
        }, gradually: false, updated: { images, _ in
            let image = images.first ?? nil
            let thumbnail = image.flatMap { videoEditorThumbnailImage($0, size: lowSize, blurred: false) }
            subscriber.putNext((image, thumbnail))
            subscriber.putCompletion()
        })
        request.start()
        return ActionDisposable { request.cancel() }
    }
}
