import Foundation
import AVFoundation
import ImageIO
import CoreServices
import TelegramCore
import TelegramContext
import SwiftSignalKit

enum AvatarMediaPreparationError: Error, Equatable {
    case generic
}

final class AvatarPreparedVideo: Equatable {
    static func == (lhs: AvatarPreparedVideo, rhs: AvatarPreparedVideo) -> Bool {
        lhs === rhs
    }

    let videoPath: String
    let thumbnailPath: String

    private let transferred = Atomic(value: false)

    private init(videoPath: String, thumbnailPath: String) {
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
    }

    func takeFiles() -> (video: String, thumbnail: String) {
        _ = self.transferred.swap(true)
        return (self.videoPath, self.thumbnailPath)
    }

    deinit {
        if !self.transferred.with({ $0 }) {
            try? FileManager.default.removeItem(atPath: self.videoPath)
            try? FileManager.default.removeItem(atPath: self.thumbnailPath)
        }
    }

    static func prepare(path: String) -> Result<AvatarPreparedVideo, AvatarMediaPreparationError> {
        let videoPath = NSTemporaryDirectory() + "tgs_\(UUID().uuidString).mp4"
        let thumbnailPath = NSTemporaryDirectory() + "tgs_\(UUID().uuidString).jpg"
        var succeeded = false
        defer {
            if !succeeded {
                try? FileManager.default.removeItem(atPath: videoPath)
                try? FileManager.default.removeItem(atPath: thumbnailPath)
            }
        }
        do {
            try FileManager.default.copyItem(atPath: path, toPath: videoPath)
            let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
            let duration = asset.duration.seconds
            guard duration.isFinite, duration > 0, !asset.tracks(withMediaType: .video).isEmpty else { return .failure(.generic) }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let image = try generator.copyCGImage(at: .zero, actualTime: nil)
            guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: thumbnailPath) as CFURL, kUTTypeJPEG, 1, nil) else { return .failure(.generic) }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return .failure(.generic) }
            succeeded = true
            return .success(AvatarPreparedVideo(videoPath: videoPath, thumbnailPath: thumbnailPath))
        } catch {
            return .failure(.generic)
        }
    }
}

func avatarMediaResourcePath(context: any AccountContextProtocol, fileReference: FileMediaReference) -> Signal<String, AvatarMediaPreparationError> {
    let mediaBox = context.account.postbox.mediaBox
    let resource = fileReference.media.resource
    let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: fileReference.userLocation, userContentType: fileReference.userContentType, reference: fileReference.resourceReference(resource), statsCategory: fileReference.media.isVideo ? .video : .file)
    let completedFetch = Signal<Void, AvatarMediaPreparationError> { subscriber in
        fetch.start(error: { _ in
            subscriber.putError(.generic)
        }, completed: {
            subscriber.putNext(())
            subscriber.putCompletion()
        })
    }
    return completedFetch |> mapToSignal { _ in
        mediaBox.resourceData(resource) |> filter { $0.complete } |> map { $0.path } |> castError(AvatarMediaPreparationError.self) |> then(.fail(.generic)) |> take(1)
    }
}
