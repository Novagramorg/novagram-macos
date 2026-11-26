import Foundation
import AVFoundation

struct EditedAvatarVideoGeometry {
    let size: CGSize
    let transform: CGAffineTransform

    init?(naturalSize: CGSize, transform: CGAffineTransform) {
        guard naturalSize.width.isFinite, naturalSize.height.isFinite, naturalSize.width > 0, naturalSize.height > 0, [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy({ $0.isFinite }) else { return nil }
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.maxX.isFinite, bounds.maxY.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let determinant = transform.a * transform.d - transform.b * transform.c
        guard determinant.isFinite, determinant != 0 else { return nil }
        self.size = bounds.size
        self.transform = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }

    func cropped(selection: CGRect, viewSize: CGSize) -> EditedAvatarVideoGeometry? {
        guard viewSize.width.isFinite, viewSize.height.isFinite, viewSize.width > 0, viewSize.height > 0, selection.origin.x.isFinite, selection.origin.y.isFinite, selection.width.isFinite, selection.height.isFinite, selection.width > 0, selection.height > 0 else { return nil }
        let scaleX = self.size.width / viewSize.width
        let scaleY = self.size.height / viewSize.height
        let rect = CGRect(x: selection.minX * scaleX, y: selection.minY * scaleY, width: selection.width * scaleX, height: selection.height * scaleY)
        guard rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return nil }
        let bounded = rect.intersection(CGRect(origin: .zero, size: self.size))
        guard !bounded.isNull, bounded.width > 0, bounded.height > 0 else { return nil }
        let side = min(bounded.width, bounded.height)
        let outputSide = max(16, floor(side / 16) * 16)
        let scale = outputSide / side
        let transform = self.transform.concatenating(CGAffineTransform(translationX: -bounded.minX, y: -bounded.minY)).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        guard scale.isFinite, [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy({ $0.isFinite }) else { return nil }
        return EditedAvatarVideoGeometry(size: CGSize(width: outputSide, height: outputSide), transform: transform)
    }

    private init(size: CGSize, transform: CGAffineTransform) {
        self.size = size
        self.transform = transform
    }
}

func editedAvatarVideoComposition(track: AVAssetTrack, duration: CMTime, selection: CGRect? = nil, viewSize: CGSize? = nil) -> AVVideoComposition? {
    guard duration.isNumeric, duration > .zero, var geometry = EditedAvatarVideoGeometry(naturalSize: track.naturalSize, transform: track.preferredTransform) else { return nil }
    if let selection {
        guard let viewSize, let cropped = geometry.cropped(selection: selection, viewSize: viewSize) else { return nil }
        geometry = cropped
    }
    let composition = AVMutableVideoComposition()
    composition.renderSize = geometry.size
    composition.frameDuration = CMTime(value: 1, timescale: 30)
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    layer.setTransform(geometry.transform, at: .zero)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [layer]
    composition.instructions = [instruction]
    return composition
}

func prepareEditedAvatarVideo(_ asset: AVAsset) -> (composition: AVMutableComposition, track: AVMutableCompositionTrack)? {
    guard asset.duration.isNumeric, asset.duration > .zero, let source = asset.tracks(withMediaType: .video).first, EditedAvatarVideoGeometry(naturalSize: source.naturalSize, transform: source.preferredTransform) != nil else { return nil }
    let composition = AVMutableComposition()
    guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
    do {
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
        track.preferredTransform = source.preferredTransform
        return (composition, track)
    } catch {
        return nil
    }
}
