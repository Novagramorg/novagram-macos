import Foundation
import AVFoundation

func recordingVideoDuration(_ asset: AVAsset) -> Double? {
    let duration = asset.duration.seconds
    guard duration.isFinite, duration > 0, Int(exactly: ceil(duration)) != nil,
        let video = asset.tracks(withMediaType: .video).first,
        video.timeRange.isValid, !video.timeRange.isEmpty,
        video.timeRange.start.isNumeric, video.timeRange.duration.isNumeric,
        video.timeRange.duration.seconds > 0 else {
        return nil
    }
    return duration
}

func recordingVideoComposition(_ segments: [URL]) -> AVMutableComposition? {
    guard !segments.isEmpty else { return nil }
    let composition = AVMutableComposition()
    for segment in segments {
        let asset = AVURLAsset(url: segment)
        guard recordingVideoDuration(asset) != nil,
            let video = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        do {
            try composition.insertTimeRange(video.timeRange, of: asset, at: composition.duration)
        } catch {
            return nil
        }
    }
    guard recordingVideoDuration(composition) != nil else { return nil }
    return composition
}
